"""PostgreSQL access. Credentials arrive as environment variables injected by ECS from Secrets Manager."""

from __future__ import annotations

import os
from functools import lru_cache

from psycopg.conninfo import make_conninfo
from psycopg.rows import dict_row
from psycopg_pool import ConnectionPool


class Repo:
    def __init__(self) -> None:
        conninfo = make_conninfo(
            host=os.environ["DB_HOST"],
            dbname=os.environ.get("DB_NAME", "app"),
            user=os.environ["DB_USER"],
            password=os.environ["DB_PASSWORD"],
            sslmode=os.environ.get("DB_SSLMODE", "require"),
            connect_timeout=5,
        )
        self.pool = ConnectionPool(conninfo, min_size=1, max_size=5, kwargs={"row_factory": dict_row}, open=True)

    def migrate(self) -> None:
        with self.pool.connection() as c:
            c.execute(
                "CREATE TABLE IF NOT EXISTS notes ("
                "id BIGSERIAL PRIMARY KEY, text VARCHAR(500) NOT NULL, created_at TIMESTAMPTZ NOT NULL DEFAULT now())"
            )

    def ping(self) -> None:
        with self.pool.connection() as c:
            c.execute("SELECT 1")

    def list(self, limit: int) -> list[dict]:
        with self.pool.connection() as c:
            rows = c.execute("SELECT id, text, created_at FROM notes ORDER BY id DESC LIMIT %s", (limit,)).fetchall()
        return [{**r, "created_at": r["created_at"].isoformat()} for r in rows]

    def add(self, text: str) -> dict:
        with self.pool.connection() as c:
            r = c.execute("INSERT INTO notes (text) VALUES (%s) RETURNING id, text, created_at", (text,)).fetchone()
        return {**r, "created_at": r["created_at"].isoformat()}


@lru_cache(maxsize=1)
def repo() -> Repo:
    return Repo()
