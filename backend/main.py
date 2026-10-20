from __future__ import annotations

import os
from contextlib import asynccontextmanager
from datetime import UTC, datetime
from pathlib import Path
from typing import Literal
from uuid import uuid4

from fastapi import FastAPI, HTTPException, Query
from pydantic import BaseModel, ConfigDict, Field
from sqlalchemy import DateTime, Integer, String, create_engine, select, text
from sqlalchemy.engine import URL
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column, sessionmaker


if "DATABASE_URL" in os.environ:
    DATABASE_URL = os.environ["DATABASE_URL"]
elif os.getenv("POSTGRES_PASSWORD"):
    DATABASE_URL = URL.create(
        drivername="postgresql+psycopg",
        username=os.getenv("POSTGRES_USER", "arena"),
        password=os.environ["POSTGRES_PASSWORD"],
        host=os.getenv("POSTGRES_HOST", "localhost"),
        port=int(os.getenv("POSTGRES_PORT", "5432")),
        database=os.getenv("POSTGRES_DB", "arena"),
    )
else:
    DATABASE_URL = "sqlite:///./data/arena.db"

if isinstance(DATABASE_URL, str) and DATABASE_URL.startswith("sqlite:///"):
    database_path = DATABASE_URL.removeprefix("sqlite:///")
    if database_path != ":memory:" and not database_path.startswith("/"):
        Path(database_path).parent.mkdir(parents=True, exist_ok=True)

engine_options: dict[str, object] = {"pool_pre_ping": True}
if isinstance(DATABASE_URL, str) and DATABASE_URL.startswith("sqlite:"):
    engine_options["connect_args"] = {"check_same_thread": False}
engine = create_engine(DATABASE_URL, **engine_options)
SessionLocal = sessionmaker(bind=engine, expire_on_commit=False)


class Base(DeclarativeBase):
    pass


class Match(Base):
    __tablename__ = "matches"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=lambda: str(uuid4()))
    map_name: Mapped[str] = mapped_column(String(48), nullable=False)
    status: Mapped[str] = mapped_column(String(16), nullable=False, default="open", index=True)
    max_players: Mapped[int] = mapped_column(Integer, nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        default=lambda: datetime.now(UTC),
    )


class MatchCreate(BaseModel):
    map_name: str = Field(min_length=1, max_length=48, pattern=r"^[a-zA-Z0-9 _-]+$")
    max_players: int = Field(default=32, ge=2, le=32)


class MatchStatusUpdate(BaseModel):
    status: Literal["open", "in_progress", "closed"]


class MatchResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: str
    map_name: str
    status: str
    max_players: int
    created_at: datetime


@asynccontextmanager
async def lifespan(_: FastAPI):
    with engine.begin() as connection:
        if connection.dialect.name == "postgresql":
            connection.execute(text("SELECT pg_advisory_xact_lock(4921037741)"))
        Base.metadata.create_all(bind=connection)
    yield


app = FastAPI(
    title="Island Arena API",
    version="1.0.0",
    lifespan=lifespan,
)


@app.get("/health")
def health() -> dict[str, str]:
    with SessionLocal() as database:
        database.execute(text("SELECT 1"))
    return {"status": "ok", "storage": "ok"}


@app.post("/v1/matches", response_model=MatchResponse, status_code=201)
def create_match(request: MatchCreate) -> Match:
    with SessionLocal.begin() as database:
        match = Match(map_name=request.map_name, max_players=request.max_players)
        database.add(match)
        database.flush()
    return match


@app.get("/v1/matches", response_model=list[MatchResponse])
def list_matches(
    status: Literal["open", "in_progress", "closed"] | None = None,
    limit: int = Query(default=50, ge=1, le=100),
) -> list[Match]:
    statement = select(Match).order_by(Match.created_at.desc()).limit(limit)
    if status is not None:
        statement = statement.where(Match.status == status)
    with SessionLocal() as database:
        return list(database.scalars(statement))


@app.patch("/v1/matches/{match_id}", response_model=MatchResponse)
def update_match_status(match_id: str, request: MatchStatusUpdate) -> Match:
    with SessionLocal.begin() as database:
        match = database.get(Match, match_id)
        if match is None:
            raise HTTPException(status_code=404, detail="Match not found.")
        match.status = request.status
        database.flush()
    return match
