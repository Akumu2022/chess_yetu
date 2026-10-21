"""Keep games in progress across server restarts.

Live games stay in memory (fast, simple); this module snapshots them to the database whenever they change
and loads them back at startup. A restart only costs the clock time between the last saved move and the
restart (the mover is given that time back), and open sockets, which reconnect by themselves.
"""
import logging
import time

import chess

from .db import LiveGame, SessionLocal
from .game import Game, _now_ms

log = logging.getLogger("chess_yetu")
KEEP_FINISHED_S = 600  # finished games stay in memory this long (reconnecting players still see the result)

_saved_sig: dict[str, tuple] = {}
_over_since: dict[str, float] = {}


def _sig(g: Game) -> tuple:
    return (g.seq, len(g.tokens), g.status, g.draw_offer, tuple(sorted(g.user_ids.items())))


def to_dict(g: Game) -> dict:
    return {
        "id": g.id, "initial_ms": g.initial_ms, "increment_ms": g.increment_ms, "tokens": g.tokens,
        "moves": g.moves, "clocks": g.live_clocks(), "status": g.status, "draw_offer": g.draw_offer,
        "user_ids": g.user_ids, "players": g.players, "kids": g.kids, "kid_ids": g.kid_ids,
        "started_wall": g.started_wall, "bot_color": g.bot_color, "bot_level": g.bot_level,
        "tournament_id": g.tournament_id,
    }


def from_dict(d: dict) -> Game:
    g = Game(id=d["id"], initial_ms=d["initial_ms"], increment_ms=d["increment_ms"])
    g.tokens = d["tokens"]
    g.user_ids = {k: int(v) for k, v in d["user_ids"].items()}
    g.kid_ids = {k: int(v) for k, v in d["kid_ids"].items()}
    g.players = d["players"]
    g.kids = d["kids"]
    g.started_wall = d["started_wall"]
    g.bot_color, g.bot_level = d["bot_color"], d["bot_level"]
    g.tournament_id = d["tournament_id"]
    g.draw_offer = d["draw_offer"]
    g.board = chess.Board()
    for uci in d["moves"]:
        g.board.push_uci(uci)
    g.moves = list(d["moves"])
    g.clocks = {"white": int(d["clocks"]["white"]), "black": int(d["clocks"]["black"])}
    g.status = d["status"]
    g.turn_started = _now_ms()  # the downtime is not charged to anyone
    return g


def flush(games: dict[str, Game]) -> int:
    """Write games that changed since the last flush; forget the ones that finished. Returns rows written."""
    written = 0
    with SessionLocal() as db:
        for gid, g in list(games.items()):
            if g.status == "over":
                if gid in _saved_sig:
                    row = db.get(LiveGame, gid)
                    if row:
                        db.delete(row)
                    _saved_sig.pop(gid, None)
                continue
            sig = _sig(g)
            if _saved_sig.get(gid) == sig:
                continue
            row = db.get(LiveGame, gid)
            if row:
                row.data = to_dict(g)
            else:
                db.add(LiveGame(game_id=gid, data=to_dict(g)))
            _saved_sig[gid] = sig
            written += 1
        db.commit()
    return written


def evict_finished(games: dict[str, Game]) -> int:
    """Drop finished games from memory once nobody needs the live view any more."""
    now = time.monotonic()
    gone = 0
    for gid, g in list(games.items()):
        if g.status != "over":
            _over_since.pop(gid, None)
            continue
        since = _over_since.setdefault(gid, now)
        if now - since > KEEP_FINISHED_S:
            del games[gid]
            _over_since.pop(gid, None)
            gone += 1
    return gone


def restore(games: dict[str, Game]) -> int:
    """Load saved games at startup."""
    n = 0
    with SessionLocal() as db:
        for row in db.query(LiveGame).all():
            if row.game_id in games:
                continue
            try:
                g = from_dict(row.data)
            except Exception:
                log.exception("could not restore game %s", row.game_id)
                db.delete(row)
                continue
            games[g.id] = g
            _saved_sig[g.id] = _sig(g)
            n += 1
        db.commit()
    return n


def reset() -> None:
    _saved_sig.clear()
    _over_since.clear()
