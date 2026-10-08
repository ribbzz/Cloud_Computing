"""
CampusPulse 2026 - backend API
NorthBridge University Smart Campus Operations Platform

Runs in a container on EC2. Talks to DynamoDB for persistence,
SSM Parameter Store for secrets, CloudWatch for metrics/logs.

Endpoints (see Appendix B of the project brief):
    GET  /health          no auth, liveness probe
    POST /login           exchange username+password for a JWT
    POST /events          ingest one campus event   (roles: device, admin)
    GET  /events          list recent events        (roles: staff, admin)
    GET  /stats           aggregated statistics     (roles: staff, admin)
    GET  /alerts          abnormal / urgent events  (role : admin only)
"""

import hashlib
import json
import logging
import os
import secrets
import time
import uuid
from datetime import datetime, timedelta, timezone
from typing import List, Optional

import boto3
import jwt
from boto3.dynamodb.conditions import Key
from fastapi import Depends, FastAPI, Header, HTTPException, Request
from pydantic import BaseModel, Field, field_validator

# --------------------------------------------------------------------------
# configuration - everything comes from the environment, nothing hardcoded
# --------------------------------------------------------------------------
REGION       = os.environ.get("AWS_REGION", "eu-west-3")
EVENTS_TABLE = os.environ.get("EVENTS_TABLE", "campuspulse-events")
USERS_TABLE  = os.environ.get("USERS_TABLE", "campuspulse-users")
JWT_PARAM    = os.environ.get("JWT_SECRET_PARAM", "/campuspulse/jwt-secret")
METRIC_NS    = os.environ.get("METRIC_NAMESPACE", "CampusPulse")
TOKEN_TTL_MIN = int(os.environ.get("TOKEN_TTL_MINUTES", "60"))
LOG_PATH     = os.environ.get("LOG_PATH", "/var/log/campuspulse/app.log")

# --------------------------------------------------------------------------
# structured logging - one JSON object per line so CloudWatch Logs Insights
# can query it with fields like  fields @timestamp, event_type, severity
# --------------------------------------------------------------------------
os.makedirs(os.path.dirname(LOG_PATH), exist_ok=True)
logger = logging.getLogger("campuspulse")
logger.setLevel(logging.INFO)
_fmt = logging.Formatter("%(message)s")
_file = logging.FileHandler(LOG_PATH)
_file.setFormatter(_fmt)
_stream = logging.StreamHandler()
_stream.setFormatter(_fmt)
logger.addHandler(_file)
logger.addHandler(_stream)


def log_json(level: str, **fields):
    fields["level"] = level
    fields["ts"] = datetime.now(timezone.utc).isoformat()
    logger.info(json.dumps(fields))


# --------------------------------------------------------------------------
# AWS clients - credentials come from the EC2 instance role, never from keys
# --------------------------------------------------------------------------
_dynamodb = boto3.resource("dynamodb", region_name=REGION)
_ssm = boto3.client("ssm", region_name=REGION)
_cw = boto3.client("cloudwatch", region_name=REGION)

events_table = _dynamodb.Table(EVENTS_TABLE)
users_table = _dynamodb.Table(USERS_TABLE)

_jwt_secret_cache = {"value": None, "fetched_at": 0.0}


def jwt_secret() -> str:
    """Read the signing key from SSM Parameter Store, cached for 5 minutes.

    The secret is never baked into the image, never in git, never in an
    environment variable on the host - only the parameter *name* travels.
    """
    now = time.time()
    if _jwt_secret_cache["value"] and now - _jwt_secret_cache["fetched_at"] < 300:
        return _jwt_secret_cache["value"]
    resp = _ssm.get_parameter(Name=JWT_PARAM, WithDecryption=True)
    _jwt_secret_cache["value"] = resp["Parameter"]["Value"]
    _jwt_secret_cache["fetched_at"] = now
    return _jwt_secret_cache["value"]


# --------------------------------------------------------------------------
# password hashing - PBKDF2-HMAC-SHA256, per-user random salt
# --------------------------------------------------------------------------
PBKDF2_ROUNDS = 200_000


def hash_password(password: str, salt: Optional[str] = None) -> str:
    salt = salt or secrets.token_hex(16)
    digest = hashlib.pbkdf2_hmac(
        "sha256", password.encode(), bytes.fromhex(salt), PBKDF2_ROUNDS
    ).hex()
    return f"pbkdf2_sha256${PBKDF2_ROUNDS}${salt}${digest}"


def verify_password(password: str, stored: str) -> bool:
    try:
        _algo, rounds, salt, digest = stored.split("$")
        candidate = hashlib.pbkdf2_hmac(
            "sha256", password.encode(), bytes.fromhex(salt), int(rounds)
        ).hex()
        return secrets.compare_digest(candidate, digest)
    except Exception:
        return False


# --------------------------------------------------------------------------
# severity classification - the "data processing" layer of the architecture
# --------------------------------------------------------------------------
THRESHOLDS = {
    "occupancy":   {"warning": 40,  "critical": 55},   # people in one room
    "temperature": {"warning": 27,  "critical": 31},   # degrees C
    "humidity":    {"warning": 65,  "critical": 80},   # percent
    "energy":      {"warning": 8.0, "critical": 12.0}, # kWh in the interval
    "door":        {"warning": 1,   "critical": 2},    # 0 closed 1 ajar 2 forced
    "request":     {"warning": 2,   "critical": 3},    # student request priority
}


def classify(event_type: str, value: float) -> str:
    """Map a raw reading onto normal / warning / critical.

    Deliberately a simple threshold rule: it is explainable in the oral
    defence and costs nothing to run. Section 15 of the brief allows
    replacing this with a statistical or ML detector later.
    """
    rules = THRESHOLDS.get(event_type)
    if not rules:
        return "normal"
    if value >= rules["critical"]:
        return "critical"
    if value >= rules["warning"]:
        return "warning"
    return "normal"


# --------------------------------------------------------------------------
# request / response models - pydantic rejects malformed input before it
# ever reaches the database (input validation = part of the threat model)
# --------------------------------------------------------------------------
class EventIn(BaseModel):
    building: str = Field(min_length=1, max_length=64)
    room: str = Field(min_length=1, max_length=64)
    event_type: str = Field(min_length=1, max_length=32)
    value: float
    unit: str = Field(min_length=1, max_length=16)
    timestamp: Optional[str] = None
    event_id: Optional[str] = None

    @field_validator("event_type")
    @classmethod
    def known_type(cls, v: str) -> str:
        v = v.lower().strip()
        if v not in THRESHOLDS:
            raise ValueError(f"unsupported event_type: {v}")
        return v

    @field_validator("building", "room")
    @classmethod
    def no_weird_chars(cls, v: str) -> str:
        cleaned = v.strip()
        if not all(c.isalnum() or c in "-_ " for c in cleaned):
            raise ValueError("only letters, digits, dash, underscore and space")
        return cleaned


class LoginIn(BaseModel):
    username: str = Field(min_length=1, max_length=64)
    password: str = Field(min_length=1, max_length=256)


# --------------------------------------------------------------------------
# authentication / authorisation
# --------------------------------------------------------------------------
app = FastAPI(title="CampusPulse 2026 API", version="1.0.0")


def current_user(authorization: str = Header(default="")) -> dict:
    if not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="missing bearer token")
    token = authorization.split(" ", 1)[1]
    try:
        claims = jwt.decode(token, jwt_secret(), algorithms=["HS256"])
    except jwt.ExpiredSignatureError:
        raise HTTPException(status_code=401, detail="token expired")
    except jwt.InvalidTokenError:
        raise HTTPException(status_code=401, detail="invalid token")
    return claims


def require_roles(*allowed: str):
    def dependency(user: dict = Depends(current_user)) -> dict:
        if user.get("role") not in allowed:
            log_json("warn", msg="authz_denied", user=user.get("sub"),
                     role=user.get("role"), needed=list(allowed))
            raise HTTPException(status_code=403, detail="insufficient role")
        return user
    return dependency


# --------------------------------------------------------------------------
# routes
# --------------------------------------------------------------------------
@app.get("/health")
def health():
    return {"status": "ok", "service": "campuspulse", "version": app.version}


@app.post("/login")
def login(body: LoginIn, request: Request):
    item = users_table.get_item(Key={"username": body.username}).get("Item")
    # same error and roughly the same work whether or not the user exists,
    # so the endpoint does not leak which usernames are valid
    stored = item["password_hash"] if item else hash_password("dummy")
    if not item or not verify_password(body.password, stored):
        log_json("warn", msg="login_failed", username=body.username,
                 src=request.client.host if request.client else "?")
        raise HTTPException(status_code=401, detail="invalid credentials")

    now = datetime.now(timezone.utc)
    claims = {
        "sub": body.username,
        "role": item["role"],
        "iat": now,
        "exp": now + timedelta(minutes=TOKEN_TTL_MIN),
    }
    token = jwt.encode(claims, jwt_secret(), algorithm="HS256")
    log_json("info", msg="login_ok", username=body.username, role=item["role"])
    return {"access_token": token, "token_type": "bearer",
            "role": item["role"], "expires_in": TOKEN_TTL_MIN * 60}


@app.post("/events", status_code=201)
def ingest_event(body: EventIn, user: dict = Depends(require_roles("device", "admin"))):
    ts = body.timestamp or datetime.now(timezone.utc).isoformat()
    event_id = body.event_id or f"evt-{uuid.uuid4().hex[:12]}"
    severity = classify(body.event_type, body.value)

    item = {
        "building": body.building,                 # partition key
        "event_ts": f"{ts}#{event_id}",            # sort key, unique per event
        "event_id": event_id,
        "room": body.room,
        "event_type": body.event_type,
        "value": str(body.value),                  # Dynamo has no float type
        "unit": body.unit,
        "severity": severity,
        "timestamp": ts,
        "ingested_by": user.get("sub"),
        "ttl": int(time.time()) + 60 * 60 * 24 * 30,   # auto-expire in 30 days
    }
    events_table.put_item(Item=item)

    log_json("info", msg="event_stored", event_id=event_id,
             building=body.building, room=body.room,
             event_type=body.event_type, value=body.value, severity=severity)

    if severity in ("warning", "critical"):
        # Publish a metric with a severity dimension; monitor metric costs.
        try:
            _cw.put_metric_data(
                Namespace=METRIC_NS,
                MetricData=[{
                    "MetricName": "AbnormalEvents",
                    "Value": 1,
                    "Unit": "Count",
                    "Dimensions": [{"Name": "Severity", "Value": severity}],
                }],
            )
        except Exception as exc:                    # never fail ingestion on
            log_json("error", msg="metric_failed", error=str(exc))   # telemetry

    return {"event_id": event_id, "severity": severity, "stored": True}


@app.get("/events")
def list_events(building: Optional[str] = None, limit: int = 50,
                user: dict = Depends(require_roles("staff", "admin"))):
    limit = max(1, min(limit, 200))
    if building:
        # Query = reads only this building's partition, cheap and fast
        resp = events_table.query(
            KeyConditionExpression=Key("building").eq(building),
            ScanIndexForward=False,     # newest first
            Limit=limit,
        )
    else:
        # Scan reads the whole table. Acceptable at prototype scale, and
        # discussed as a known limitation in the report.
        resp = events_table.scan(Limit=limit * 4)
    items = sorted(resp.get("Items", []),
                   key=lambda i: i.get("timestamp", ""), reverse=True)[:limit]
    return {"count": len(items), "items": items}


@app.get("/stats")
def stats(user: dict = Depends(require_roles("staff", "admin"))):
    resp = events_table.scan()
    items = resp.get("Items", [])
    while "LastEvaluatedKey" in resp and len(items) < 5000:
        resp = events_table.scan(ExclusiveStartKey=resp["LastEvaluatedKey"])
        items.extend(resp.get("Items", []))

    per_building, per_type, severities = {}, {}, {}
    energy_by_building, occupancy_peak = {}, {}

    for it in items:
        b = it.get("building", "unknown")
        t = it.get("event_type", "unknown")
        s = it.get("severity", "normal")
        try:
            v = float(it.get("value", 0))
        except (TypeError, ValueError):
            v = 0.0
        per_building[b] = per_building.get(b, 0) + 1
        per_type[t] = per_type.get(t, 0) + 1
        severities[s] = severities.get(s, 0) + 1
        if t == "energy":
            energy_by_building[b] = round(energy_by_building.get(b, 0.0) + v, 2)
        if t == "occupancy":
            key = f"{b}/{it.get('room', '?')}"
            occupancy_peak[key] = max(occupancy_peak.get(key, 0), v)

    top_energy = sorted(energy_by_building.items(), key=lambda kv: -kv[1])[:5]
    busiest = sorted(occupancy_peak.items(), key=lambda kv: -kv[1])[:5]

    return {
        "total_events": len(items),
        "events_per_building": per_building,
        "events_per_type": per_type,
        "severity_breakdown": severities,
        "top_energy_consumers_kwh": [{"building": b, "kwh": v} for b, v in top_energy],
        "busiest_rooms": [{"room": r, "peak_occupancy": v} for r, v in busiest],
        "generated_at": datetime.now(timezone.utc).isoformat(),
    }


@app.get("/alerts")
def alerts(limit: int = 50, user: dict = Depends(require_roles("admin"))):
    """Admin-only. This is the endpoint demonstrated for role-based access."""
    limit = max(1, min(limit, 200))
    out = []
    for sev in ("critical", "warning"):
        resp = events_table.query(
            IndexName="severity-index",
            KeyConditionExpression=Key("severity").eq(sev),
            ScanIndexForward=False,
            Limit=limit,
        )
        out.extend(resp.get("Items", []))
    out.sort(key=lambda i: i.get("timestamp", ""), reverse=True)
    log_json("info", msg="alerts_read", user=user.get("sub"), returned=len(out[:limit]))
    return {"count": len(out[:limit]), "items": out[:limit]}
