"""FastAPI app: accounts, quick match, game creation (REST) and live play (WebSocket)."""
import asyncio
import logging
import os
import random
import secrets
import time
from contextlib import asynccontextmanager
from typing import Literal

from fastapi import Depends, FastAPI, Header, HTTPException, WebSocket, WebSocketDisconnect
from starlette.websockets import WebSocketDisconnected
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field

from . import auth, bot, matchmaking
from .db import Child, GameRecord, KidGameRecord, SessionLocal, User, init_db
from .game import Game, GameError
from .glicko2 import Rating
from .glicko2 import update as glicko_update

log = logging.getLogger("chess_yetu")
PROTOCOL_VERSION = 1
RECONNECT_GRACE_S = 45
IDLE_TIMEOUT_S = 15  # clients ping every 5s; silence this long means the link is dead

games: dict[str, Game] = {}
sockets: dict[str, dict[str, WebSocket]] = {}  # game_id -> color -> socket
bot_tasks: dict[str, asyncio.Task] = {}  # game_id -> task while the computer is thinking
last_say: dict[tuple[str, str], float] = {}  # (game_id, color) -> when they last chatted
rtt_ms: dict[tuple[str, str], int] = {}  # (game_id, color) -> last measured round trip


class NewGame(BaseModel):
    minutes: int = Field(10, ge=1, le=180)
    increment: int = Field(0, ge=0, le=60)


class NewBotGame(NewGame):
    level: int = Field(2, ge=1, le=5)
    color: Literal["white", "black", "random"] = "random"


class Credentials(BaseModel):
    username: str
    password: str = Field(min_length=8, max_length=128)


# ---- live-game helpers ----------------------------------------------------

async def _send(ws: WebSocket, msg: dict) -> None:
    try:
        await ws.send_json(msg)
    except Exception:
        pass  # a dead socket is handled by its own receive loop


async def _broadcast(game_id: str, msg: dict) -> None:
    for ws in list(sockets.get(game_id, {}).values()):
        await _send(ws, msg)


def _apply_ratings(game: Game, white, black) -> dict[str, float]:
    """Glicko-2 update for both players (User or Child rows); returns the rating changes."""
    rw, rb = Rating(white.rating, white.rd, white.vol), Rating(black.rating, black.rd, black.vol)
    sw = {"1-0": 1.0, "0-1": 0.0}.get(game.result, 0.5)
    nw = glicko_update(rw, [(rb, sw)])
    nb = glicko_update(rb, [(rw, 1 - sw)])
    for row, new in ((white, nw), (black, nb)):
        row.rating, row.rd, row.vol = new.rating, new.rd, new.vol
        row.games += 1
    return {"white": nw.rating - rw.rating, "black": nb.rating - rb.rating}


def _finalize(game: Game) -> dict | None:
    """Save the finished game and, if rated, update both Glicko-2 ratings. Runs once per game."""
    if game.finalized:
        return None
    game.finalized = True
    deltas = {"white": 0.0, "black": 0.0}
    with SessionLocal() as db:
        if game.kids:
            # Kids' games live in their own tables and rating pool.
            if game.rated:
                deltas = _apply_ratings(game, db.get(Child, game.kid_ids["white"]),
                                        db.get(Child, game.kid_ids["black"]))
            db.add(KidGameRecord(
                id=game.id, white_child_id=game.kid_ids.get("white"),
                black_child_id=game.kid_ids.get("black"), bot_level=game.bot_level,
                moves=game.moves, result=game.result, reason=game.reason, rated=game.rated,
                duration_s=int(time.time() - game.started_wall) if game.started_wall else 0,
                white_delta=deltas["white"], black_delta=deltas["black"]))
        else:
            if game.rated:
                deltas = _apply_ratings(game, db.get(User, game.user_ids["white"]),
                                        db.get(User, game.user_ids["black"]))
            db.add(GameRecord(
                id=game.id, white_id=game.user_ids.get("white"), black_id=game.user_ids.get("black"),
                moves=game.moves, result=game.result, reason=game.reason, rated=game.rated,
                initial_ms=game.initial_ms, increment_ms=game.increment_ms,
                white_delta=deltas["white"], black_delta=deltas["black"]))
        db.commit()
    if game.tournament_id is not None:
        from . import tournaments
        tournaments.on_game_finished(game)
    return {c: round(d, 1) for c, d in deltas.items()} if game.rated else None


async def _game_over(game: Game) -> None:
    changes = _finalize(game)
    await _broadcast(game.id, {"type": "game_over", "result": game.result,
                               "reason": game.reason, "rating_change": changes})


def _kick_bot(game: Game) -> None:
    """Start the computer's move if it is its turn and it isn't already thinking."""
    if game.bot_to_move and game.id not in bot_tasks:
        task = asyncio.create_task(_bot_move(game))
        bot_tasks[game.id] = task
        task.add_done_callback(lambda _: bot_tasks.pop(game.id, None))


async def _bot_move(game: Game) -> None:
    started = time.monotonic()
    try:
        uci = await bot.choose_move(game.board.copy(), game.bot_level, game.live_clocks()[game.bot_color])
        # Even instant replies should feel like a person thinking: a short, slightly varied pause
        # so the player can see the computer's turn happen instead of a piece suddenly appearing.
        await asyncio.sleep(max(0.0, random.uniform(0.9, 1.6) - (time.monotonic() - started)))
        if not game.bot_to_move:
            return  # the game ended (resign / flag) while it was thinking
        made = game.play(game.bot_color, game.seq + 1, uci)
        await _broadcast(game.id, {"type": "move_made", **made})
        if game.status == "over":
            await _game_over(game)
    except GameError as e:
        if e.code == "timeout":
            await _game_over(game)
        else:
            log.error("bot move rejected: %s", e)
    except Exception:
        log.exception("computer opponent failed")
        await _broadcast(game.id, {"type": "error", "code": "engine_failed",
                                   "message": "The computer opponent had a problem"})


async def _flag_watcher() -> None:
    """Ends games whose side-to-move ran out of time even if nobody sends a message."""
    while True:
        await asyncio.sleep(0.5)
        for game in list(games.values()):
            if game.check_flag():
                await _game_over(game)


async def _persist_loop() -> None:
    from . import persistence
    while True:
        await asyncio.sleep(1)
        try:
            persistence.flush(games)
            persistence.evict_finished(games)
        except Exception:
            log.exception("saving live games failed")


@asynccontextmanager
async def lifespan(_: FastAPI):
    init_db()
    from . import persistence, tournaments
    restored = persistence.restore(games)
    if restored:
        log.info("restored %d games in progress", restored)
    tasks = [asyncio.create_task(_flag_watcher()), asyncio.create_task(tournaments.pairing_loop(games)),
             asyncio.create_task(_persist_loop())]
    yield
    for task in tasks:
        task.cancel()
    persistence.flush(games)  # a clean shutdown loses nothing


app = FastAPI(title="Chess Yetu", lifespan=lifespan)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["http://localhost:5273", "http://127.0.0.1:5273",
                   *filter(None, os.environ.get("CORS_ORIGINS", "").split(","))],
    allow_origin_regex=r"http://(192\.168|10\.)\d*\.\d+\.\d+:5273",  # phones on the LAN
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.get("/health")
def health():
    return {"ok": True, "protocol": PROTOCOL_VERSION}


# ---- accounts -------------------------------------------------------------

def _public(user: User) -> dict:
    return {"id": user.id, "username": user.username, "rating": round(user.rating),
            "rd": round(user.rd), "games": user.games}


@app.post("/auth/register")
def register(body: Credentials):
    if not auth.USERNAME_RE.match(body.username):
        raise HTTPException(422, "Username must be 3-24 letters, digits or underscores")
    with SessionLocal() as db:
        if db.query(User).filter(User.username.ilike(body.username)).first():
            raise HTTPException(409, "That username is taken")
        user = User(username=body.username, pw_hash=auth.hash_password(body.password))
        db.add(user)
        db.commit()
    return {"token": auth.make_token(user), "user": _public(user)}


@app.post("/auth/login")
def login(body: Credentials):
    with SessionLocal() as db:
        user = db.query(User).filter(User.username.ilike(body.username)).first()
    if not user or not auth.verify_password(body.password, user.pw_hash):
        raise HTTPException(401, "Wrong username or password")
    return {"token": auth.make_token(user), "user": _public(user)}


@app.get("/me")
def me(user: User = Depends(auth.require_user)):
    with SessionLocal() as db:
        return _public(db.get(User, user.id))  # fresh rating, not the token-time copy


@app.get("/me/games")
def my_games(user: User = Depends(auth.require_user)):
    with SessionLocal() as db:
        rows = (db.query(GameRecord)
                .filter((GameRecord.white_id == user.id) | (GameRecord.black_id == user.id))
                .order_by(GameRecord.played_at.desc()).limit(20).all())
    return [{"id": r.id, "result": r.result, "reason": r.reason, "rated": r.rated,
             "color": "white" if r.white_id == user.id else "black",
             "delta": round(r.white_delta if r.white_id == user.id else r.black_delta, 1),
             "moves": len(r.moves), "played_at": r.played_at.isoformat()} for r in rows]


# ---- games ----------------------------------------------------------------

def _seat(game: Game, user: User | None, color: str | None = None) -> tuple[str, str]:
    if user:
        return game.add_player(user.id, user.username, user.rating, color)
    return game.add_player(color=color)


@app.post("/games")
def create_game(body: NewGame, user: User | None = Depends(auth.optional_user)):
    game = Game(id=secrets.token_urlsafe(6), initial_ms=body.minutes * 60_000,
                increment_ms=body.increment * 1000)
    games[game.id] = game
    color, token = _seat(game, user)
    return {"game_id": game.id, "color": color, "token": token}


@app.get("/bot")
def bot_info():
    return {"available": bot.available(),
            "levels": [{"level": n, "name": c["name"], "elo": c["elo"]} for n, c in bot.LEVELS.items()]}


@app.post("/games/ai")
def create_bot_game(body: NewBotGame, user: User | None = Depends(auth.optional_user)):
    """Play the computer. Always unrated, and open to guests."""
    if not bot.available():
        raise HTTPException(503, "The computer opponent is not installed on this server")
    human = random.choice(["white", "black"]) if body.color == "random" else body.color
    game = Game(id=secrets.token_urlsafe(6), initial_ms=body.minutes * 60_000,
                increment_ms=body.increment * 1000)
    games[game.id] = game
    color, token = _seat(game, user, human)
    game.seat_bot("black" if human == "white" else "white", body.level,
                  bot.label(body.level), bot.display_rating(body.level))
    return {"game_id": game.id, "color": color, "token": token}


@app.post("/games/{game_id}/join")
async def join_game(game_id: str, user: User | None = Depends(auth.optional_user)):
    game = games.get(game_id)
    if not game:
        raise HTTPException(404, "No such game")
    if game.kids:
        raise HTTPException(403, "This is a kids game")
    if user:
        # Signed in and already seated here (e.g. the tab was closed and the link reopened): hand the seat back.
        for seated, uid in game.user_ids.items():
            if uid == user.id:
                return {"game_id": game_id, "color": seated, "token": game.tokens[seated]}
    try:
        color, token = _seat(game, user)
    except GameError as e:
        raise HTTPException(409, str(e))
    await _broadcast(game_id, {"type": "game_started", **game.snapshot()})
    return {"game_id": game_id, "color": color, "token": token}


@app.get("/games/{game_id}")
def get_game(game_id: str):
    game = games.get(game_id)
    if not game:
        raise HTTPException(404, "No such game")
    return game.snapshot()


# ---- quick match ----------------------------------------------------------

@app.post("/queue")
def join_queue(body: NewGame, user: User = Depends(auth.require_user)):
    """Enter the queue, or pair at once. Then poll GET /queue until status is 'matched'."""
    existing = matchmaking.queue.get(user.id)
    if existing and time.monotonic() - existing.last_seen < 4:
        # Another tab/device on this account is polling right now; it can't pair with itself.
        return {"status": "waiting", "already_searching": True}
    matchmaking.matched.pop(user.id, None)
    me = matchmaking.Entry(user.id, user.username, user.rating, body.minutes, body.increment)
    other = matchmaking.find_opponent(me)
    if not other:
        matchmaking.queue[user.id] = me
        return {"status": "waiting"}
    del matchmaking.queue[other.user_id]
    white, black = matchmaking.randomize_colors(me, other)
    game = Game(id=secrets.token_urlsafe(6), initial_ms=body.minutes * 60_000,
                increment_ms=body.increment * 1000)
    games[game.id] = game
    for e in (white, black):
        color, token = game.add_player(e.user_id, e.name, e.rating)
        matchmaking.matched[e.user_id] = {"game_id": game.id, "color": color, "token": token}
    return {"status": "matched", "seat": matchmaking.matched.pop(user.id)}


@app.get("/queue")
def poll_queue(user: User = Depends(auth.require_user)):
    seat = matchmaking.matched.pop(user.id, None)
    if seat:
        return {"status": "matched", "seat": seat}
    entry = matchmaking.queue.get(user.id)
    if not entry:
        return {"status": "idle"}
    entry.last_seen = time.monotonic()
    return {"status": "waiting"}


@app.delete("/queue")
def leave_queue(user: User = Depends(auth.require_user)):
    matchmaking.queue.pop(user.id, None)
    return {"status": "idle"}


# ---- live play ------------------------------------------------------------

@app.websocket("/ws/games/{game_id}")
async def game_socket(ws: WebSocket, game_id: str):
    await ws.accept()
    game = games.get(game_id)
    if not game:
        await _send(ws, {"type": "error", "code": "no_such_game"})
        await ws.close()
        return

    color: str | None = None
    try:
        # The first message must be `hello`; it authenticates the connection.
        hello = await asyncio.wait_for(ws.receive_json(), timeout=10)
        if hello.get("type") != "hello":
            raise GameError("expected_hello")
        if hello.get("v") != PROTOCOL_VERSION:
            raise GameError("bad_version")
        color = game.color_for(hello.get("token"))
        if color is None:
            raise GameError("bad_token")
    except (GameError, asyncio.TimeoutError, ValueError) as e:
        await _send(ws, {"type": "error", "code": getattr(e, "code", "bad_hello")})
        await ws.close()
        return
    except (WebSocketDisconnect, WebSocketDisconnected):
        return

    sockets.setdefault(game_id, {})[color] = ws
    # Reconnect means resume: always hand back the authoritative state.
    await _send(ws, {"type": "resync", "you": color, **game.snapshot()})
    await _broadcast(game_id, {"type": "opponent_status", "color": color, "connected": True})
    _kick_bot(game)  # e.g. the computer plays white and must open

    try:
        while True:
            msg = await asyncio.wait_for(ws.receive_json(), timeout=IDLE_TIMEOUT_S)
            await _handle(game, color, ws, msg)
    except (WebSocketDisconnect, WebSocketDisconnected, asyncio.TimeoutError):
        # WebSocketDisconnected: a failed send already marked the socket dead (a phone that dropped
        # off the network), so the next read raises this instead of the usual disconnect.
        pass
    finally:
        if sockets.get(game_id, {}).get(color) is ws:
            del sockets[game_id][color]
            await _broadcast(game_id, {"type": "opponent_status", "color": color,
                                       "connected": False, "grace_s": RECONNECT_GRACE_S})


async def _handle(game: Game, color: str, ws: WebSocket, msg: dict) -> None:
    kind = msg.get("type")
    try:
        if kind == "ping":
            # Client echoes back its last measured RTT so the server can credit lag.
            if isinstance(msg.get("rtt"), int):
                rtt_ms[(game.id, color)] = msg["rtt"]
            await _send(ws, {"type": "pong", "t": msg.get("t")})
        elif kind == "move":
            credit = rtt_ms.get((game.id, color), 0) // 2
            made = game.play(color, msg.get("seq"), msg.get("move", ""), credit)
            await _broadcast(game.id, {"type": "move_made", **made})
            if game.status == "over":
                await _game_over(game)
            else:
                _kick_bot(game)
        elif kind == "say":
            # Kids never type free text: only ids from a fixed list are accepted and relayed.
            from .kids import PHRASES
            if not game.kids:
                raise GameError("chat_disabled")
            if msg.get("id") not in PHRASES:
                raise GameError("bad_phrase")
            now = time.monotonic()
            if now - last_say.get((game.id, color), 0) < 1.5:
                raise GameError("too_fast")
            last_say[(game.id, color)] = now
            await _broadcast(game.id, {"type": "said", "by": color, "id": msg["id"]})
        elif kind == "resign":
            game.resign(color)
            await _game_over(game)
        elif kind == "draw" and game.bot_color:
            # The computer accepts a draw only if it isn't better, and not in the opening.
            if game.status != "active":
                raise GameError("not_active")
            bot_is_white = game.bot_color == "white"
            score = await bot.score_for_side_to_move(game.board.copy(), bot_is_white)
            if score <= 0 and len(game.moves) >= 20:
                game.draw_offer = color
                game.offer_draw(game.bot_color)
                await _game_over(game)
            else:
                await _send(ws, {"type": "draw_declined"})
        elif kind == "draw":
            if game.offer_draw(color):
                await _game_over(game)
            else:
                await _broadcast(game.id, {"type": "draw_offered", "by": color})
        else:
            raise GameError("unknown_message", str(kind))
    except GameError as e:
        await _send(ws, {"type": "error", "code": e.code, "message": str(e)})
        if e.code == "timeout":
            await _game_over(game)


# ---- who am I -------------------------------------------------------------

@app.get("/whoami")
def whoami(authorization: str | None = Header(None)):
    """Tells the web app whether this sign-in is an adult, a child's session, or a guest."""
    token = auth._bearer(authorization)
    if not token:
        return {"kind": "guest"}
    if (child := auth.child_from_token(token)):
        return {"kind": "kid", "child": kids._child_public(child)}
    if (user := auth.user_from_token(token)):
        with SessionLocal() as db:
            return {"kind": "adult", "user": _public(db.get(User, user.id))}
    raise HTTPException(401, "Sign in required")


from . import kids, leaderboard, puzzles, review, tournaments  # noqa: E402  (registered last: it uses the shared state defined above)

app.include_router(kids.router)
app.include_router(puzzles.router)
app.include_router(review.router)
app.include_router(leaderboard.router)
app.include_router(tournaments.router)
