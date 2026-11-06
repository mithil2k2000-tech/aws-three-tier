"""Notes API: the application tier. Stateless; all state is in PostgreSQL."""

from __future__ import annotations

import json
import logging
import os
import sys
import time
from contextlib import asynccontextmanager

from fastapi import FastAPI, HTTPException, Request
from pydantic import BaseModel, Field

from src import db


class JsonFormatter(logging.Formatter):
    def format(self, record: logging.LogRecord) -> str:
        payload = {"level": record.levelname, "msg": record.getMessage(), "logger": record.name}
        payload.update(getattr(record, "extra_fields", {}))
        return json.dumps(payload)


handler = logging.StreamHandler(sys.stdout)
handler.setFormatter(JsonFormatter())
logging.basicConfig(level=logging.INFO, handlers=[handler], force=True)
log = logging.getLogger("api")

VERSION = os.environ.get("APP_VERSION", "dev")
# Game-day switch: a release built with BREAK_HEALTHCHECK=true fails its health check, so ECS rolls it back.
BROKEN = os.environ.get("BREAK_HEALTHCHECK", "false") == "true"


@asynccontextmanager
async def lifespan(app: FastAPI):
    db.repo().migrate()
    yield


app = FastAPI(title="three-tier notes", lifespan=lifespan, docs_url=None, redoc_url=None, openapi_url=None)


@app.middleware("http")
async def access_log(request: Request, call_next):
    start = time.perf_counter()
    response = await call_next(request)
    if request.url.path != "/api/healthz":
        log.info(
            "request",
            extra={
                "extra_fields": {
                    "path": request.url.path,
                    "method": request.method,
                    "status": response.status_code,
                    "ms": round((time.perf_counter() - start) * 1000, 1),
                }
            },
        )
    response.headers["Cache-Control"] = "no-store"
    return response


class NoteIn(BaseModel):
    text: str = Field(min_length=1, max_length=500)


@app.get("/api/healthz")
def healthz() -> dict:
    if BROKEN:
        raise HTTPException(status_code=503, detail="deliberately broken release")
    try:
        db.repo().ping()
    except Exception as exc:  # any DB failure means unhealthy
        log.error("db ping failed", extra={"extra_fields": {"error": type(exc).__name__}})
        raise HTTPException(status_code=503, detail="database unavailable") from exc
    return {"status": "ok", "version": VERSION}


@app.get("/api/notes")
def list_notes(limit: int = 20) -> list[dict]:
    return db.repo().list(min(max(limit, 1), 100))


@app.post("/api/notes", status_code=201)
def add_note(note: NoteIn) -> dict:
    return db.repo().add(note.text)
