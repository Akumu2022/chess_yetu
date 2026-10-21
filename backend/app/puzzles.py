"""Mate puzzles with a daily limit and a protected streak. Works for adults and for kids sessions.

The client never receives a solution: it sends the moves it has played and the server checks them with
the mate solver, answering with the defender's reply or "wrong".
"""
import json
import random
from datetime import datetime, timedelta, timezone
from pathlib import Path

import chess
from fastapi import APIRouter, Header, HTTPException
from pydantic import BaseModel, Field

from . import auth
from .db import Child, PuzzleSolve, PuzzleStreak, SessionLocal
from .mates import best_reply, forcing_moves

router = APIRouter(prefix="/puzzles", tags=["puzzles"])

EAT = timezone(timedelta(hours=3))
DAILY_LIMIT = 3  # the free allowance in the product plan; paid tiers will lift it
FREEZE_EVERY = 7  # a streak freeze is earned every 7 days, up to MAX_FREEZES
MAX_FREEZES = 2

_DATA = Path(__file__).parent / "data" / "puzzles.json"
PUZZLES: list[dict] = sorted(json.loads(_DATA.read_text()), key=lambda p: (p["depth"], p["id"])) if _DATA.exists() else []
BY_ID = {p["id"]: p for p in PUZZLES}


def _today() -> str:
    return datetime.now(EAT).strftime("%Y-%m-%d")


def _day_before(day: str, n: int = 1) -> str:
    return (datetime.strptime(day, "%Y-%m-%d") - timedelta(days=n)).strftime("%Y-%m-%d")


def _owner(authorization: str | None) -> tuple[str, int]:
    token = auth._bearer(authorization)
    payload = auth._decode(token)
    if payload and payload.get("typ") == "kid":
        child = auth.child_from_token(token)
        if child:
            return "child", child.id
    elif payload:
        user = auth.user_from_token(token)
        if user:
            return "user", user.id
    raise HTTPException(401, "Sign in to play puzzles")


def _streak_view(row: PuzzleStreak | None) -> dict:
    """What to show now: a streak is alive if the last solve was today, yesterday, or the gap can be frozen."""
    if not row or not row.last_day or row.current == 0:
        return {"current": 0, "best": row.best if row else 0, "freezes": row.freezes if row else 1}
    today = _today()
    alive = (
        row.last_day in (today, _day_before(today))
        or (row.last_day == _day_before(today, 2) and row.freezes > 0)
    )
    return {"current": row.current if alive else 0, "best": row.best, "freezes": row.freezes}


def _solved_today(db, kind: str, oid: int) -> int:
    return db.query(PuzzleSolve).filter_by(owner_kind=kind, owner_id=oid, day=_today()).count()


def _state(db, kind: str, oid: int) -> dict:
    n = _solved_today(db, kind, oid)
    return {
        "solved_today": n,
        "limit": DAILY_LIMIT,
        "streak": _streak_view(db.get(PuzzleStreak, (kind, oid))),
    }


def _record_solve(db, kind: str, oid: int, puzzle_id: int) -> None:
    today = _today()
    if db.query(PuzzleSolve).filter_by(owner_kind=kind, owner_id=oid, puzzle_id=puzzle_id).first():
        return  # re-solving an old puzzle is fine but earns nothing
    db.add(PuzzleSolve(owner_kind=kind, owner_id=oid, puzzle_id=puzzle_id, day=today))
    s = db.get(PuzzleStreak, (kind, oid))
    if not s:
        s = PuzzleStreak(owner_kind=kind, owner_id=oid, current=0, best=0, freezes=1)
        db.add(s)
    if s.last_day == today:
        pass
    elif s.last_day == _day_before(today):
        s.current += 1
    elif s.last_day == _day_before(today, 2) and s.freezes > 0:
        s.freezes -= 1  # one missed day is forgiven
        s.current += 1
    else:
        s.current = 1
    if s.last_day != today and s.current and s.current % FREEZE_EVERY == 0 and s.freezes < MAX_FREEZES:
        s.freezes += 1
    s.last_day = today
    s.best = max(s.best, s.current)
    db.commit()


def _public(p: dict) -> dict:
    board = chess.Board(p["fen"])
    return {"id": p["id"], "fen": p["fen"], "depth": p["depth"], "theme": p["theme"],
            "to_move": "white" if board.turn else "black"}


@router.get("/today")
def today(authorization: str | None = Header(None)):
    kind, oid = _owner(authorization)
    with SessionLocal() as db:
        return {**_state(db, kind, oid), "available": len(PUZZLES)}


@router.get("/next")
def next_puzzle(authorization: str | None = Header(None)):
    kind, oid = _owner(authorization)
    if not PUZZLES:
        raise HTTPException(503, "No puzzles installed")
    with SessionLocal() as db:
        state = _state(db, kind, oid)
        if state["solved_today"] >= DAILY_LIMIT:
            return {"limit_reached": True, **state}
        done = {r.puzzle_id for r in db.query(PuzzleSolve).filter_by(owner_kind=kind, owner_id=oid)}
        fresh = [p for p in PUZZLES if p["id"] not in done]
        # Gentle ladder: easiest unsolved first; once everything is solved, repeat at random.
        pick = fresh[0] if fresh else random.choice(PUZZLES)
        return {"puzzle": _public(pick), **state}


class MoveBody(BaseModel):
    played: list[str] = Field(min_length=1, max_length=4)  # my moves so far, in UCI


@router.post("/{puzzle_id}/move")
def play(puzzle_id: int, body: MoveBody, authorization: str | None = Header(None)):
    kind, oid = _owner(authorization)
    p = BY_ID.get(puzzle_id)
    if not p:
        raise HTTPException(404, "No such puzzle")
    with SessionLocal() as db:
        state = _state(db, kind, oid)
        already = db.query(PuzzleSolve).filter_by(owner_kind=kind, owner_id=oid, puzzle_id=puzzle_id).first()
        if state["solved_today"] >= DAILY_LIMIT and not already:
            raise HTTPException(403, "That's all the puzzles for today. Come back tomorrow!")

        board = chess.Board(p["fen"])
        remaining = p["depth"]
        reply = None
        for i, uci in enumerate(body.played):
            try:
                mv = chess.Move.from_uci(uci)
            except ValueError:
                return {"status": "wrong"}
            if mv not in forcing_moves(board, remaining):
                return {"status": "wrong"}
            board.push(mv)
            remaining -= 1
            if board.is_checkmate():
                _record_solve(db, kind, oid, puzzle_id)
                return {"status": "solved", **_state(db, kind, oid)}
            r = best_reply(board, remaining)
            if r is None:
                return {"status": "wrong"}
            reply = r
            board.push(r)
        return {"status": "continue", "reply": reply.uci()}
