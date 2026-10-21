import os
from datetime import datetime, timezone

from sqlalchemy import JSON, DateTime, ForeignKey, String, create_engine
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column, sessionmaker
from sqlalchemy.pool import StaticPool

DATABASE_URL = os.environ.get("DATABASE_URL", "sqlite:///chess_yetu.db")

_kwargs: dict = {}
if DATABASE_URL.startswith("sqlite"):
    _kwargs["connect_args"] = {"check_same_thread": False}
    if ":memory:" in DATABASE_URL:
        _kwargs["poolclass"] = StaticPool  # one shared connection so tables persist

engine = create_engine(DATABASE_URL, **_kwargs)
SessionLocal = sessionmaker(engine, expire_on_commit=False)


class Base(DeclarativeBase):
    pass


class User(Base):
    __tablename__ = "users"

    id: Mapped[int] = mapped_column(primary_key=True)
    username: Mapped[str] = mapped_column(String(24), unique=True, index=True)
    pw_hash: Mapped[str] = mapped_column(String(200))
    rating: Mapped[float] = mapped_column(default=1500.0)
    rd: Mapped[float] = mapped_column(default=350.0)
    vol: Mapped[float] = mapped_column(default=0.06)
    games: Mapped[int] = mapped_column(default=0)


class GameRecord(Base):
    __tablename__ = "game_records"

    id: Mapped[str] = mapped_column(String(16), primary_key=True)
    white_id: Mapped[int | None] = mapped_column(ForeignKey("users.id"), nullable=True)
    black_id: Mapped[int | None] = mapped_column(ForeignKey("users.id"), nullable=True)
    moves: Mapped[list] = mapped_column(JSON)
    result: Mapped[str] = mapped_column(String(8))
    reason: Mapped[str] = mapped_column(String(32))
    rated: Mapped[bool] = mapped_column(default=False)
    initial_ms: Mapped[int]
    increment_ms: Mapped[int]
    white_delta: Mapped[float] = mapped_column(default=0.0)
    black_delta: Mapped[float] = mapped_column(default=0.0)
    played_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=lambda: datetime.now(timezone.utc)
    )


class ParentSettings(Base):
    """Per-parent settings for the kids section. The PIN guards leaving kids mode."""
    __tablename__ = "parent_settings"

    user_id: Mapped[int] = mapped_column(ForeignKey("users.id"), primary_key=True)
    pin_hash: Mapped[str] = mapped_column(String(200))


class Child(Base):
    """A child profile. Minimal data on purpose: generated nickname, birth year, level."""
    __tablename__ = "children"

    id: Mapped[int] = mapped_column(primary_key=True)
    parent_id: Mapped[int] = mapped_column(ForeignKey("users.id"), index=True)
    nickname: Mapped[str] = mapped_column(String(32), unique=True, index=True)
    birth_year: Mapped[int]
    rating: Mapped[float] = mapped_column(default=1500.0)  # separate Glicko-2 pool from adults
    rd: Mapped[float] = mapped_column(default=350.0)
    vol: Mapped[float] = mapped_column(default=0.06)
    games: Mapped[int] = mapped_column(default=0)
    daily_limit_min: Mapped[int] = mapped_column(default=60)
    consent_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))


class KidGameRecord(Base):
    __tablename__ = "kid_game_records"

    id: Mapped[str] = mapped_column(String(16), primary_key=True)
    white_child_id: Mapped[int | None] = mapped_column(ForeignKey("children.id"), nullable=True, index=True)
    black_child_id: Mapped[int | None] = mapped_column(ForeignKey("children.id"), nullable=True, index=True)
    bot_level: Mapped[int | None] = mapped_column(nullable=True)
    moves: Mapped[list] = mapped_column(JSON)
    result: Mapped[str] = mapped_column(String(8))
    reason: Mapped[str] = mapped_column(String(32))
    rated: Mapped[bool] = mapped_column(default=False)
    duration_s: Mapped[int] = mapped_column(default=0)
    white_delta: Mapped[float] = mapped_column(default=0.0)
    black_delta: Mapped[float] = mapped_column(default=0.0)
    played_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=lambda: datetime.now(timezone.utc)
    )


class PuzzleSolve(Base):
    """One solved puzzle per owner. owner_kind is 'user' or 'child'; deleting a child erases theirs."""
    __tablename__ = "puzzle_solves"

    id: Mapped[int] = mapped_column(primary_key=True)
    owner_kind: Mapped[str] = mapped_column(String(8), index=True)
    owner_id: Mapped[int] = mapped_column(index=True)
    puzzle_id: Mapped[int]
    day: Mapped[str] = mapped_column(String(10))  # EAT calendar day, YYYY-MM-DD
    solved_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=lambda: datetime.now(timezone.utc)
    )


class PuzzleStreak(Base):
    __tablename__ = "puzzle_streaks"

    owner_kind: Mapped[str] = mapped_column(String(8), primary_key=True)
    owner_id: Mapped[int] = mapped_column(primary_key=True)
    current: Mapped[int] = mapped_column(default=0)
    best: Mapped[int] = mapped_column(default=0)
    last_day: Mapped[str | None] = mapped_column(String(10), nullable=True)
    freezes: Mapped[int] = mapped_column(default=1)  # a missed day is forgiven once per freeze


class GameAnalysis(Base):
    """Stockfish's review of a finished game, computed once and kept."""
    __tablename__ = "game_analyses"

    game_id: Mapped[str] = mapped_column(String(16), primary_key=True)
    data: Mapped[dict] = mapped_column(JSON)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=lambda: datetime.now(timezone.utc)
    )


class Tournament(Base):
    """An arena: a fixed time window in which joined players are paired again and again; points decide."""
    __tablename__ = "tournaments"

    id: Mapped[int] = mapped_column(primary_key=True)
    name: Mapped[str] = mapped_column(String(60))
    creator_id: Mapped[int] = mapped_column(ForeignKey("users.id"), index=True)
    minutes: Mapped[int]
    increment: Mapped[int]
    starts_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    duration_min: Mapped[int]
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=lambda: datetime.now(timezone.utc)
    )


class TournamentPlayer(Base):
    __tablename__ = "tournament_players"

    tournament_id: Mapped[int] = mapped_column(ForeignKey("tournaments.id"), primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id"), primary_key=True)
    active: Mapped[bool] = mapped_column(default=True)  # False after withdrawing
    points: Mapped[int] = mapped_column(default=0)  # win 2, draw 1, loss 0
    games: Mapped[int] = mapped_column(default=0)
    wins: Mapped[int] = mapped_column(default=0)
    draws: Mapped[int] = mapped_column(default=0)
    losses: Mapped[int] = mapped_column(default=0)


class TournamentGame(Base):
    __tablename__ = "tournament_games"

    game_id: Mapped[str] = mapped_column(String(16), primary_key=True)
    tournament_id: Mapped[int] = mapped_column(ForeignKey("tournaments.id"), index=True)
    white_id: Mapped[int] = mapped_column(ForeignKey("users.id"))
    black_id: Mapped[int] = mapped_column(ForeignKey("users.id"))
    result: Mapped[str | None] = mapped_column(String(8), nullable=True)  # None while being played


class LiveGame(Base):
    """Snapshot of a game in progress, so a server restart does not end it."""
    __tablename__ = "live_games"

    game_id: Mapped[str] = mapped_column(String(16), primary_key=True)
    data: Mapped[dict] = mapped_column(JSON)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=lambda: datetime.now(timezone.utc)
    )


def init_db() -> None:
    Base.metadata.create_all(engine)
