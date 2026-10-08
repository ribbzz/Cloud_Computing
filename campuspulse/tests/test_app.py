"""Offline API and account-maintenance checks; no real AWS credentials or writes."""
import copy
import os
from pathlib import Path
import sys
import tempfile
from unittest.mock import MagicMock

os.environ.update(AWS_ACCESS_KEY_ID="offline-test", AWS_SECRET_ACCESS_KEY="offline-test",
                  AWS_EC2_METADATA_DISABLED="true", LOG_PATH=str(Path(tempfile.gettempdir()) / "campuspulse-test.log"))
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "app"))
import main
import manage_user
import pytest
from fastapi.testclient import TestClient


@pytest.fixture
def client(monkeypatch):
    monkeypatch.setattr(main, "events_table", MagicMock())
    monkeypatch.setattr(main, "users_table", MagicMock())
    monkeypatch.setattr(main, "_cw", MagicMock())
    monkeypatch.setattr(main, "jwt_secret", lambda: "offline-signing-secret-for-tests-only")
    return TestClient(main.app)


def token(client, role):
    main.users_table.get_item.return_value = {"Item": {
        "username": "test-user", "role": role,
        "password_hash": main.hash_password("test-password-only")}}
    response = client.post("/login", json={"username": "test-user", "password": "test-password-only"})
    assert response.status_code == 200
    return {"Authorization": "Bearer " + response.json()["access_token"]}


def test_staff_cannot_read_alerts_or_ingest(client):
    headers = token(client, "staff")
    assert client.get("/alerts", headers=headers).status_code == 403
    assert client.post("/events", headers=headers, json={}).status_code == 403
    main.events_table.put_item.assert_not_called()
    main.events_table.query.assert_not_called()


def test_admin_alerts_and_wrong_password(client):
    headers = token(client, "admin")
    main.events_table.query.return_value = {"Items": []}
    assert client.get("/alerts", headers=headers).status_code == 200
    assert client.post("/login", json={"username": "test-user", "password": "wrong"}).status_code == 401
    assert client.get("/alerts").status_code == 401


def test_device_ingestion_classifies_and_emits_metric(client):
    headers = token(client, "device")
    event = dict(building="Library-A", room="A101", event_type="temperature", value=36, unit="celsius")
    response = client.post("/events", headers=headers, json=event)
    assert response.status_code == 201
    assert response.json()["severity"] == "critical"
    stored = main.events_table.put_item.call_args.kwargs["Item"]
    assert stored["severity"] == "critical" and stored["ingested_by"] == "test-user"
    main._cw.put_metric_data.assert_called_once()
    assert client.get("/stats", headers=headers).status_code == 403
    assert client.post("/events", headers=headers, json={**event, "event_type": "banana"}).status_code == 422


class MemoryUsers:
    def __init__(self, item=None):
        self.item = copy.deepcopy(item)
        self.writes = []
    def get_item(self, **kwargs):
        return {"Item": copy.deepcopy(self.item)} if self.item else {}
    def put_item(self, **kwargs):
        self.writes.append(copy.deepcopy(kwargs))
        self.item = copy.deepcopy(kwargs["Item"])


def test_reset_preserves_attributes_and_checks_previous_hash(monkeypatch):
    original = dict(username="front.desk", role="staff", description="keep me",
                    password_hash=main.hash_password("old-test-password"))
    table = MemoryUsers(original)
    monkeypatch.setattr(manage_user, "users_table", table)
    monkeypatch.setattr(sys, "argv", ["manage_user.py", "front.desk", "--role", "staff"])
    monkeypatch.setattr(manage_user, "getpass", lambda prompt: "new-test-password")
    manage_user.main()
    assert main.verify_password("new-test-password", table.item["password_hash"])
    assert table.item["description"] == "keep me" and table.item["role"] == "staff"
    assert table.writes[0]["ExpressionAttributeValues"][":old"] == original["password_hash"]


def test_reset_refuses_role_change(monkeypatch):
    table = MemoryUsers(dict(username="front.desk", role="staff", password_hash="unused"))
    monkeypatch.setattr(manage_user, "users_table", table)
    monkeypatch.setattr(sys, "argv", ["manage_user.py", "front.desk", "--role", "admin"])
    with pytest.raises(SystemExit):
        manage_user.main()
    assert not table.writes


def test_create_has_no_overwrite_condition(monkeypatch):
    table = MemoryUsers()
    monkeypatch.setattr(manage_user, "users_table", table)
    monkeypatch.setattr(sys, "argv", ["manage_user.py", "sensor.fleet", "--role", "device", "--create"])
    monkeypatch.setattr(manage_user, "getpass", lambda prompt: "device-test-password")
    manage_user.main()
    assert table.writes[0]["ConditionExpression"] == "attribute_not_exists(username)"
    assert table.item["role"] == "device"
