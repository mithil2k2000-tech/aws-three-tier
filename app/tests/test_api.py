from datetime import UTC, datetime

import pytest
from fastapi.testclient import TestClient

from src import db, main


class FakeRepo:
    def __init__(self, healthy=True):
        self.rows, self.healthy = [], healthy

    def migrate(self):
        pass

    def ping(self):
        if not self.healthy:
            raise ConnectionError("down")

    def list(self, limit):
        return list(reversed(self.rows))[:limit]

    def add(self, text):
        row = {"id": len(self.rows) + 1, "text": text, "created_at": datetime.now(UTC).isoformat()}
        self.rows.append(row)
        return row


@pytest.fixture
def client(monkeypatch):
    fake = FakeRepo()
    monkeypatch.setattr(db, "repo", lambda: fake)
    with TestClient(main.app) as c:
        yield c, fake


def test_health_ok(client):
    c, _ = client
    r = c.get("/api/healthz")
    assert r.status_code == 200 and r.json()["status"] == "ok"
    assert r.headers["cache-control"] == "no-store"


def test_health_fails_when_db_down(client):
    c, fake = client
    fake.healthy = False
    assert c.get("/api/healthz").status_code == 503


def test_broken_release_fails_health(client, monkeypatch):
    c, _ = client
    monkeypatch.setattr(main, "BROKEN", True)
    assert c.get("/api/healthz").status_code == 503


def test_create_and_list(client):
    c, _ = client
    assert c.post("/api/notes", json={"text": "hello"}).status_code == 201
    c.post("/api/notes", json={"text": "world"})
    assert [n["text"] for n in c.get("/api/notes").json()] == ["world", "hello"]


def test_validation(client):
    c, _ = client
    assert c.post("/api/notes", json={"text": ""}).status_code == 422
    assert c.post("/api/notes", json={"text": "x" * 501}).status_code == 422
