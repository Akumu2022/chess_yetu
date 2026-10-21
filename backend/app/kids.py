"""Chess for kids: parent-managed child profiles, kids-only play, safety rules enforced by the server.

Rules from the proposal, all enforced here and not only in the screens:
  * a parent creates the child's account and consent is logged;
  * minimal data (generated nickname, birth year), no free text anywhere;
  * kids play only kids and bots, in their own rating pool;
  * a kids session can't reach adult features, and leaving it needs the parent's PIN;
  * parents can set daily time limits and delete all of a child's data.
"""
import random
import secrets
import time
from datetime import datetime, timedelta, timezone
from typing import Literal

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field
from sqlalchemy import func, or_

from . import auth, bot, matchmaking
from .db import Child, KidGameRecord, ParentSettings, PuzzleSolve, PuzzleStreak, SessionLocal, User
from .game import Game

router = APIRouter(prefix="/kids", tags=["kids"])

MIN_AGE, MAX_AGE = 5, 13  # teenagers: policy still to be decided
MAX_CHILDREN = 6
EAT = timezone(timedelta(hours=3))  # Kenya has no daylight saving

# The only things a child can say. The server relays ids, never text.
PHRASES = {
    "hi": "Hello!",
    "gl": "Good luck!",
    "nm": "Nice move!",
    "oops": "Oops!",
    "wp": "Well played!",
    "ty": "Thank you!",
    "gg": "Good game!",
    "rm": "Rematch?",
}

# Friendly computer opponents: personality name -> engine level
BOTS = {
    1: {"name": "Zuri the Gentle", "level": 1},
    2: {"name": "Simba the Brave", "level": 2},
    3: {"name": "Mzee Kobe the Wise", "level": 3},
}

ADJECTIVES = ["Swift", "Brave", "Clever", "Bright", "Happy", "Mighty", "Kind", "Quick", "Calm", "Bold"]
ANIMALS = ["Simba", "Twiga", "Tembo", "Duma", "Kiboko", "Chui", "Nyati", "Kasuku", "Fisi", "Ndovu"]

_pin_state: dict[int, list] = {}  # parent id -> [wrong attempts, locked until]


def _core():
    from . import main  # imported late: main registers this router at its very end

    return main


# ---- helpers ----------------------------------------------------------------

def _today_start_utc() -> datetime:
    """Midnight in Kenya, as a naive UTC time (how the database stores it)."""
    start = datetime.now(EAT).replace(hour=0, minute=0, second=0, microsecond=0)
    return start.astimezone(timezone.utc).replace(tzinfo=None)


def _minutes_today(db, child_id: int) -> int:
    secs = (db.query(func.coalesce(func.sum(KidGameRecord.duration_s), 0))
            .filter(or_(KidGameRecord.white_child_id == child_id, KidGameRecord.black_child_id == child_id))
            .filter(KidGameRecord.played_at >= _today_start_utc()).scalar())
    return (secs + 59) // 60


def _child_public(child: Child) -> dict:
    with SessionLocal() as db:
        fresh = db.get(Child, child.id) or child
        used = _minutes_today(db, child.id)
    return {"id": fresh.id, "nickname": fresh.nickname, "rating": round(fresh.rating),
            "rd": round(fresh.rd), "games": fresh.games, "birth_year": fresh.birth_year,
            "daily_limit_min": fresh.daily_limit_min, "minutes_today": used,
            "minutes_left": max(0, fresh.daily_limit_min - used)}


def _require_time_left(child: Child) -> None:
    if _child_public(child)["minutes_left"] <= 0:
        raise HTTPException(403, "Time's up for today! Come back tomorrow.")


def _new_nickname(db) -> str:
    for _ in range(50):
        name = f"{random.choice(ADJECTIVES)}{random.choice(ANIMALS)}{random.randint(100, 999)}"
        if not db.query(Child).filter(Child.nickname == name).first():
            return name
    raise HTTPException(500, "Could not make a nickname")


def _own_child(db, parent: User, child_id: int) -> Child:
    child = db.get(Child, child_id)
    if not child or child.parent_id != parent.id:
        raise HTTPException(404, "No such child")
    return child


def _check_pin(parent_id: int, pin: str) -> None:
    state = _pin_state.setdefault(parent_id, [0, 0.0])
    if time.monotonic() < state[1]:
        raise HTTPException(429, "Too many wrong PINs. Try again in a few minutes.")
    with SessionLocal() as db:
        row = db.get(ParentSettings, parent_id)
    if not row or not auth.verify_password(pin, row.pin_hash):
        state[0] += 1
        if state[0] >= 5:
            state[0], state[1] = 0, time.monotonic() + 300
        raise HTTPException(403, "Wrong PIN")
    state[0] = 0


# ---- parent: PIN and children ---------------------------------------------------

class PinBody(BaseModel):
    pin: str = Field(pattern=r"^\d{4,6}$")
    current: str | None = None  # required when changing an existing PIN


@router.get("/pin")
def pin_status(parent: User = Depends(auth.require_user)):
    with SessionLocal() as db:
        return {"set": db.get(ParentSettings, parent.id) is not None}


@router.put("/pin")
def set_pin(body: PinBody, parent: User = Depends(auth.require_user)):
    with SessionLocal() as db:
        row = db.get(ParentSettings, parent.id)
    if row:
        if not body.current:
            raise HTTPException(422, "Enter your current PIN to change it")
        _check_pin(parent.id, body.current)
    with SessionLocal() as db:
        db.merge(ParentSettings(user_id=parent.id, pin_hash=auth.hash_password(body.pin)))
        db.commit()
    return {"set": True}


class NewChild(BaseModel):
    birth_year: int
    consent: bool = False


@router.post("/children")
def create_child(body: NewChild, parent: User = Depends(auth.require_user)):
    if not body.consent:
        raise HTTPException(422, "A parent or guardian must give consent to create a child profile")
    age = datetime.now(EAT).year - body.birth_year
    if not MIN_AGE <= age <= MAX_AGE:
        raise HTTPException(422, f"Chess for kids is for ages {MIN_AGE} to {MAX_AGE}")
    with SessionLocal() as db:
        if db.query(Child).filter(Child.parent_id == parent.id).count() >= MAX_CHILDREN:
            raise HTTPException(409, f"You can add up to {MAX_CHILDREN} children")
        child = Child(parent_id=parent.id, nickname=_new_nickname(db), birth_year=body.birth_year,
                      consent_at=datetime.now(timezone.utc))
        db.add(child)
        db.commit()
    return _child_public(child)


@router.get("/children")
def list_children(parent: User = Depends(auth.require_user)):
    with SessionLocal() as db:
        children = db.query(Child).filter(Child.parent_id == parent.id).order_by(Child.id).all()
    return [_child_public(c) for c in children]


class ChildSettings(BaseModel):
    daily_limit_min: int = Field(ge=10, le=240)


@router.patch("/children/{child_id}")
def update_child(child_id: int, body: ChildSettings, parent: User = Depends(auth.require_user)):
    with SessionLocal() as db:
        child = _own_child(db, parent, child_id)
        child.daily_limit_min = body.daily_limit_min
        db.commit()
    return _child_public(child)


@router.delete("/children/{child_id}")
def delete_child(child_id: int, parent: User = Depends(auth.require_user)):
    """Erase the child and everything about them. Opponents keep their own history, minus this child."""
    with SessionLocal() as db:
        child = _own_child(db, parent, child_id)
        db.query(KidGameRecord).filter(KidGameRecord.white_child_id == child.id).update({"white_child_id": None})
        db.query(KidGameRecord).filter(KidGameRecord.black_child_id == child.id).update({"black_child_id": None})
        db.query(KidGameRecord).filter(KidGameRecord.white_child_id.is_(None),
                                       KidGameRecord.black_child_id.is_(None)).delete()
        db.query(PuzzleSolve).filter_by(owner_kind="child", owner_id=child.id).delete()
        db.query(PuzzleStreak).filter_by(owner_kind="child", owner_id=child.id).delete()
        db.delete(child)
        db.commit()
    matchmaking.kid_queue.pop(child_id, None)
    return {"deleted": True}


def _games_for(child_id: int) -> list[dict]:
    with SessionLocal() as db:
        rows = (db.query(KidGameRecord)
                .filter(or_(KidGameRecord.white_child_id == child_id, KidGameRecord.black_child_id == child_id))
                .order_by(KidGameRecord.played_at.desc()).limit(20).all())
    out = []
    for r in rows:
        mine = "white" if r.white_child_id == child_id else "black"
        if r.bot_level:
            opponent = BOTS.get(r.bot_level, {}).get("name", "Computer")
        else:
            opponent = "Another kid"
        out.append({"id": r.id, "result": r.result, "reason": r.reason, "color": mine,
                    "opponent": opponent, "rated": r.rated, "moves": len(r.moves),
                    "minutes": (r.duration_s + 59) // 60,
                    "delta": round(r.white_delta if mine == "white" else r.black_delta, 1),
                    "played_at": r.played_at.isoformat()})
    return out


@router.get("/children/{child_id}/games")
def child_games(child_id: int, parent: User = Depends(auth.require_user)):
    with SessionLocal() as db:
        _own_child(db, parent, child_id)
    return _games_for(child_id)


@router.post("/children/{child_id}/session")
def start_session(child_id: int, parent: User = Depends(auth.require_user)):
    """Hand the device to the child. A PIN must exist first, or there would be no way to lock it."""
    with SessionLocal() as db:
        child = _own_child(db, parent, child_id)
        if not db.get(ParentSettings, parent.id):
            raise HTTPException(409, "Set a parent PIN first")
    return {"token": auth.make_kid_token(child), "child": _child_public(child)}


# ---- child: profile, leaving kids mode ----------------------------------------------

@router.get("/me")
def kid_me(child: Child = Depends(auth.require_child)):
    return _child_public(child)


@router.get("/me/games")
def kid_games(child: Child = Depends(auth.require_child)):
    return _games_for(child.id)


@router.get("/phrases")
def phrases():
    return PHRASES


class ExitBody(BaseModel):
    pin: str


@router.post("/exit")
def exit_kids_mode(body: ExitBody, child: Child = Depends(auth.require_child)):
    """Back to the parent's own account; only the parent's PIN opens this door."""
    _check_pin(child.parent_id, body.pin)
    with SessionLocal() as db:
        parent = db.get(User, child.parent_id)
    return {"token": auth.make_token(parent), "user": _core()._public(parent)}


# ---- child: games ---------------------------------------------------------------------

class KidGameOptions(BaseModel):
    minutes: int = Field(10, ge=5, le=30)
    increment: int = Field(5, ge=0, le=10)


class KidBotGame(KidGameOptions):
    bot: int = Field(1, ge=1, le=3)
    color: Literal["white", "black", "random"] = "random"


def _new_kid_game(opts: KidGameOptions) -> Game:
    game = Game(id=secrets.token_urlsafe(6), initial_ms=opts.minutes * 60_000,
                increment_ms=opts.increment * 1000, kids=True)
    _core().games[game.id] = game
    return game


@router.post("/games/ai")
def kid_bot_game(body: KidBotGame, child: Child = Depends(auth.require_child)):
    _require_time_left(child)
    if not bot.available():
        raise HTTPException(503, "The computer opponent is not available right now")
    mine = random.choice(["white", "black"]) if body.color == "random" else body.color
    game = _new_kid_game(body)
    color, token = game.add_player(name=child.nickname, rating=child.rating, color=mine, kid_id=child.id)
    pal = BOTS[body.bot]
    game.seat_bot("black" if mine == "white" else "white", pal["level"], pal["name"], None)
    return {"game_id": game.id, "color": color, "token": token}


@router.post("/queue")
def kid_join_queue(body: KidGameOptions, child: Child = Depends(auth.require_child)):
    """Kids-only matchmaking: this pool never touches the adult queue."""
    _require_time_left(child)
    existing = matchmaking.kid_queue.get(child.id)
    if existing and time.monotonic() - existing.last_seen < 4:
        return {"status": "waiting", "already_searching": True}
    matchmaking.kid_matched.pop(child.id, None)
    me = matchmaking.Entry(child.id, child.nickname, child.rating, body.minutes, body.increment)
    other = matchmaking.find_opponent(me, matchmaking.kid_queue)
    if not other:
        matchmaking.kid_queue[child.id] = me
        return {"status": "waiting"}
    del matchmaking.kid_queue[other.user_id]
    white, black = matchmaking.randomize_colors(me, other)
    game = _new_kid_game(body)
    for e in (white, black):
        color, token = game.add_player(name=e.name, rating=e.rating, kid_id=e.user_id)
        matchmaking.kid_matched[e.user_id] = {"game_id": game.id, "color": color, "token": token}
    return {"status": "matched", "seat": matchmaking.kid_matched.pop(child.id)}


@router.get("/queue")
def kid_poll_queue(child: Child = Depends(auth.require_child)):
    seat = matchmaking.kid_matched.pop(child.id, None)
    if seat:
        return {"status": "matched", "seat": seat}
    entry = matchmaking.kid_queue.get(child.id)
    if not entry:
        return {"status": "idle"}
    entry.last_seen = time.monotonic()
    return {"status": "waiting"}


@router.delete("/queue")
def kid_leave_queue(child: Child = Depends(auth.require_child)):
    matchmaking.kid_queue.pop(child.id, None)
    return {"status": "idle"}
