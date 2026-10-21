"""Arena tournaments: a time window in which joined players are paired again and again; points decide.

Scoring is win 2, draw 1, loss 0. Players are paired only while their tournament page is open (it polls
`/me` as a heartbeat), so nobody is matched with someone who walked away. Games are rated like any other.
"""
import asyncio
import logging
import random
import secrets
import time
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field

from . import auth
from .db import Tournament, TournamentGame, TournamentPlayer, SessionLocal, User
from .game import Game

log = logging.getLogger("chess_yetu")
router = APIRouter(prefix="/tournaments", tags=["tournaments"])

PRESENT_S = 10  # a player counts as here if their page polled within this many seconds
STOP_PAIRING_S = 30  # no new games in the last seconds of the window
MAX_OPEN_PER_CREATOR = 3
REPEAT_AFTER_S = 20  # the same two players may meet again back-to-back only after waiting this long

present: dict[tuple[int, int], float] = {}  # (tournament, user) -> last heartbeat (monotonic)
waiting_since: dict[tuple[int, int], float] = {}
assigned: dict[tuple[int, int], dict] = {}  # seat waiting to be picked up by the player's next poll
last_opponent: dict[tuple[int, int], int] = {}


def utc(dt: datetime) -> datetime:
    return dt if dt.tzinfo else dt.replace(tzinfo=timezone.utc)


def now() -> datetime:
    return datetime.now(timezone.utc)


def ends_at(t: Tournament) -> datetime:
    return utc(t.starts_at) + timedelta(minutes=t.duration_min)


def reset() -> None:
    for d in (present, waiting_since, assigned, last_opponent):
        d.clear()


@dataclass
class Cand:
    user_id: int
    points: int
    waited: float  # seconds spent waiting for a game


def pick_pairs(cands: list[Cand], last_opp: dict[int, int]) -> list[tuple[Cand, Cand]]:
    """Pair neighbours in the standings; avoid an immediate rematch unless someone has waited a while."""
    pool = sorted(cands, key=lambda c: (-c.points, c.user_id))
    pairs = []
    while len(pool) >= 2:
        a = pool.pop(0)
        pick = None
        for b in pool:
            rematch = last_opp.get(a.user_id) == b.user_id or last_opp.get(b.user_id) == a.user_id
            if not rematch or min(a.waited, b.waited) >= REPEAT_AFTER_S:
                pick = b
                break
        if pick is None:
            continue  # a has nobody new to play yet
        pool.remove(pick)
        pairs.append((a, pick))
    return pairs


def status_of(t: Tournament, games_live: dict[str, Game]) -> str:
    n = now()
    if n < utc(t.starts_at):
        return "upcoming"
    if n < ends_at(t):
        return "running"
    # the window is over; it is finished once the last game ends
    live = any(g.tournament_id == t.id and g.status != "over" for g in games_live.values())
    return "finishing" if live else "finished"


def _standings(db, tid: int) -> list[dict]:
    rows = (db.query(TournamentPlayer, User).join(User, User.id == TournamentPlayer.user_id)
            .filter(TournamentPlayer.tournament_id == tid).all())
    out = [{"username": u.username, "rating": round(u.rating), "points": p.points, "games": p.games,
            "wins": p.wins, "draws": p.draws, "losses": p.losses, "active": p.active}
           for p, u in rows]
    out.sort(key=lambda r: (-r["points"], -r["wins"], r["games"], r["username"]))
    for i, r in enumerate(out, 1):
        r["rank"] = i
    return out


def pair_once(games_live: dict[str, Game]) -> int:
    """One pairing pass over every running tournament. Returns how many games were created."""
    created = 0
    mono = time.monotonic()
    with SessionLocal() as db:
        running = [t for t in db.query(Tournament).all()
                   if utc(t.starts_at) <= now() < ends_at(t) - timedelta(seconds=STOP_PAIRING_S)]
        for t in running:
            busy = {uid for g in games_live.values() if g.tournament_id == t.id and g.status != "over"
                    for uid in g.user_ids.values()}
            players = db.query(TournamentPlayer).filter_by(tournament_id=t.id, active=True).all()
            cands = []
            for p in players:
                key = (t.id, p.user_id)
                if (p.user_id in busy or key in assigned or mono - present.get(key, -1e9) > PRESENT_S):
                    waiting_since.pop(key, None)
                    continue
                waiting_since.setdefault(key, mono)
                cands.append(Cand(p.user_id, p.points, mono - waiting_since[key]))
            last = {c.user_id: last_opponent.get((t.id, c.user_id), -1) for c in cands}
            for a, b in pick_pairs(cands, last):
                ua, ub = db.get(User, a.user_id), db.get(User, b.user_id)
                white, black = (ua, ub) if random.random() < 0.5 else (ub, ua)
                game = Game(id=secrets.token_urlsafe(6), initial_ms=t.minutes * 60_000,
                            increment_ms=t.increment * 1000)
                game.tournament_id = t.id
                games_live[game.id] = game
                for u in (white, black):
                    color, token = game.add_player(u.id, u.username, u.rating, "white" if u is white else "black")
                    assigned[(t.id, u.id)] = {"game_id": game.id, "color": color, "token": token}
                    waiting_since.pop((t.id, u.id), None)
                last_opponent[(t.id, ua.id)] = ub.id
                last_opponent[(t.id, ub.id)] = ua.id
                db.add(TournamentGame(game_id=game.id, tournament_id=t.id, white_id=white.id, black_id=black.id))
                created += 1
            db.commit()
    return created


async def pairing_loop(games_live: dict[str, Game]) -> None:
    while True:
        await asyncio.sleep(2)
        try:
            pair_once(games_live)
        except Exception:
            log.exception("tournament pairing failed")


def on_game_finished(game: Game) -> None:
    """Called once when a tournament game ends: award points."""
    if game.tournament_id is None or len(game.user_ids) != 2:
        return
    with SessionLocal() as db:
        tg = db.get(TournamentGame, game.id)
        if not tg or tg.result is not None:
            return
        tg.result = game.result
        for color, uid in game.user_ids.items():
            p = db.get(TournamentPlayer, (game.tournament_id, uid))
            if not p:
                continue
            p.games += 1
            if game.result == "1/2-1/2":
                p.points += 1
                p.draws += 1
            elif (game.result == "1-0") == (color == "white"):
                p.points += 2
                p.wins += 1
            else:
                p.losses += 1
        db.commit()


# ---- API ------------------------------------------------------------------

class NewTournament(BaseModel):
    name: str = Field(min_length=3, max_length=60)
    minutes: int = Field(ge=1, le=30)
    increment: int = Field(0, ge=0, le=30)
    starts_in_min: int = Field(5, ge=0, le=7 * 24 * 60)
    duration_min: int = Field(30, ge=10, le=180)


def _live() -> dict[str, Game]:
    from .main import games  # the shared live-game table
    return games


def _public(t: Tournament, db, user: User | None) -> dict:
    n_players = db.query(TournamentPlayer).filter_by(tournament_id=t.id, active=True).count()
    joined = bool(user and (p := db.get(TournamentPlayer, (t.id, user.id))) and p.active)
    creator = db.get(User, t.creator_id)
    return {"id": t.id, "name": t.name, "minutes": t.minutes, "increment": t.increment,
            "starts_at": utc(t.starts_at).isoformat(), "ends_at": ends_at(t).isoformat(),
            "duration_min": t.duration_min, "status": status_of(t, _live()), "players": n_players,
            "joined": joined, "creator": creator.username if creator else None}


@router.post("")
def create(body: NewTournament, user: User = Depends(auth.require_user)):
    with SessionLocal() as db:
        mine = [t for t in db.query(Tournament).filter_by(creator_id=user.id).all()
                if status_of(t, _live()) in ("upcoming", "running")]
        if len(mine) >= MAX_OPEN_PER_CREATOR:
            raise HTTPException(429, f"You already have {MAX_OPEN_PER_CREATOR} open tournaments")
        t = Tournament(name=body.name.strip(), creator_id=user.id, minutes=body.minutes, increment=body.increment,
                       starts_at=now() + timedelta(minutes=body.starts_in_min), duration_min=body.duration_min)
        db.add(t)
        db.commit()
        return _public(t, db, user)


@router.get("")
def list_tournaments(user: User | None = Depends(auth.optional_user)):
    with SessionLocal() as db:
        items = [_public(t, db, user) for t in db.query(Tournament).order_by(Tournament.starts_at.desc()).limit(40)]
    order = {"running": 0, "finishing": 0, "upcoming": 1, "finished": 2}
    items.sort(key=lambda t: (order[t["status"]], t["starts_at"] if t["status"] != "finished" else ""))
    return items[:20]


def _get(db, tid: int) -> Tournament:
    t = db.get(Tournament, tid)
    if not t:
        raise HTTPException(404, "No such tournament")
    return t


@router.get("/{tid}")
def detail(tid: int, user: User | None = Depends(auth.optional_user)):
    with SessionLocal() as db:
        t = _get(db, tid)
        info = _public(t, db, user)
        standings = _standings(db, tid)
    return {**info, "standings": standings,
            "winner": standings[0]["username"] if info["status"] == "finished" and standings and standings[0]["games"] else None}


@router.post("/{tid}/join")
def join(tid: int, user: User = Depends(auth.require_user)):
    with SessionLocal() as db:
        t = _get(db, tid)
        if now() >= ends_at(t):
            raise HTTPException(409, "This tournament has ended")
        p = db.get(TournamentPlayer, (tid, user.id))
        if p:
            p.active = True
        else:
            db.add(TournamentPlayer(tournament_id=tid, user_id=user.id))
        db.commit()
    present[(tid, user.id)] = time.monotonic()
    return {"joined": True}


@router.delete("/{tid}/join")
def leave(tid: int, user: User = Depends(auth.require_user)):
    with SessionLocal() as db:
        p = db.get(TournamentPlayer, (tid, user.id))
        if p:
            if p.games == 0:
                db.delete(p)
            else:
                p.active = False
            db.commit()
    present.pop((tid, user.id), None)
    assigned.pop((tid, user.id), None)
    return {"joined": False}


@router.get("/{tid}/me")
def me(tid: int, user: User = Depends(auth.require_user)):
    """Heartbeat plus pickup: poll this while the tournament page is open."""
    with SessionLocal() as db:
        p = db.get(TournamentPlayer, (tid, user.id))
        if not p or not p.active:
            return {"status": "not_joined"}
    key = (tid, user.id)
    present[key] = time.monotonic()
    seat = assigned.pop(key, None)
    if seat:
        return {"status": "matched", "seat": seat}
    return {"status": "waiting"}
