"""
CampusPulse 2026 - simulated campus sensor fleet.

Stands in for the IoT devices the brief describes: classrooms, libraries,
labs, energy meters, doors and student service requests. Authenticates once
as the 'device' role, then POSTs events to the API on a fixed interval and
occasionally injects an anomaly so the alerting path can be demonstrated
live during the defence.

    python simulate.py --api http://<EC2-PUBLIC-IP>/api \
                       --user sensor.fleet \
                       --rate 2 --duration 300 --anomaly 0.08

Run it from your laptop: it proves the platform ingests from outside the VPC.
"""
import argparse
from getpass import getpass
import json
import random
import sys
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone

BUILDINGS = {
    "Library-A":   ["A101", "A203", "A310"],
    "ScienceLab-B": ["B012", "B114"],
    "LectureHall-C": ["C001", "C002", "C100"],
    "Admin-D":     ["D201"],
}

# event_type -> (unit, normal low, normal high, anomaly low, anomaly high)
PROFILES = {
    "occupancy":   ("people",  0,  35,  45,  70),
    "temperature": ("celsius", 18, 25,  29,  36),
    "humidity":    ("percent", 35, 60,  68,  92),
    "energy":      ("kwh",     0.5, 6.0, 9.0, 15.0),
    "door":        ("state",   0,  0,   1,   2),
    "request":     ("priority", 1, 1,   2,   3),
}


def post(url: str, payload: dict, token: str = "", timeout: int = 10):
    data = json.dumps(payload).encode()
    req = urllib.request.Request(url, data=data, method="POST")
    req.add_header("Content-Type", "application/json")
    if token:
        req.add_header("Authorization", "Bearer " + token)
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return json.loads(resp.read().decode())


def login(api: str, user: str, password: str) -> str:
    out = post(f"{api}/login", {"username": user, "password": password})
    print(f"authenticated as {user} (role: {out['role']})")
    return out["access_token"]


def make_event(anomaly_rate: float) -> dict:
    building = random.choice(list(BUILDINGS))
    room = random.choice(BUILDINGS[building])
    etype = random.choice(list(PROFILES))
    unit, lo, hi, alo, ahi = PROFILES[etype]
    abnormal = random.random() < anomaly_rate
    low, high = (alo, ahi) if abnormal else (lo, hi)
    value = (round(random.uniform(low, high), 2)
             if isinstance(low, float) or isinstance(high, float)
             else random.randint(int(low), int(high)))
    return {
        "building": building,
        "room": room,
        "event_type": etype,
        "value": value,
        "unit": unit,
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--api", required=True, help="e.g. http://51.44.x.x/api")
    ap.add_argument("--user", default="sensor.fleet")
    ap.add_argument("--password", help="Omit to enter password at a hidden prompt")
    ap.add_argument("--rate", type=float, default=2.0, help="events per second")
    ap.add_argument("--duration", type=int, default=120, help="seconds, 0 = forever")
    ap.add_argument("--anomaly", type=float, default=0.08, help="0..1 abnormal share")
    args = ap.parse_args()
    if args.password is None:
        args.password = getpass("Account password: ")

    api = args.api.rstrip("/")
    try:
        token = login(api, args.user, args.password)
    except urllib.error.HTTPError as e:
        print(f"login failed: {e.code} {e.read().decode()[:200]}")
        return 1
    except Exception as e:
        print(f"cannot reach {api}: {e}")
        return 1

    interval = 1.0 / max(args.rate, 0.01)
    started = time.time()
    sent = abnormal = failed = 0

    print(f"sending ~{args.rate}/s to {api}/events - ctrl-c to stop")
    try:
        while args.duration == 0 or time.time() - started < args.duration:
            ev = make_event(args.anomaly)
            try:
                out = post(f"{api}/events", ev, token)
                sent += 1
                if out.get("severity") != "normal":
                    abnormal += 1
                    print(f"  {out['severity']:8} {ev['building']}/{ev['room']} "
                          f"{ev['event_type']}={ev['value']}{ev['unit']}")
            except urllib.error.HTTPError as e:
                failed += 1
                if e.code == 401:            # token expired mid-run
                    token = login(api, args.user, args.password)
                else:
                    print(f"  HTTP {e.code}: {e.read().decode()[:120]}")
            except Exception as e:
                failed += 1
                print(f"  network error: {e}")
            time.sleep(interval)
    except KeyboardInterrupt:
        pass

    elapsed = time.time() - started
    print(f"\nsent {sent} events in {elapsed:.0f}s "
          f"({sent/max(elapsed,1):.1f}/s), {abnormal} abnormal, {failed} failed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
