"""Stockfish opponent. One short-lived engine process per move keeps this simple and crash-proof.

Stockfish is GPL-3.0. It only ever runs on the server and is never shipped inside the apps.
"""
import asyncio
import os
import random
import shutil
from pathlib import Path

import chess
import chess.engine

ENGINE_DIR = Path(__file__).resolve().parent.parent / "engines"

# level -> display name, UCI_Elo (None = not limited), and whether it plays weak on purpose
LEVELS: dict[int, dict] = {
    1: {"name": "Beginner", "elo": 800, "skill": 0, "depth": 1, "blunder": 0.30},
    2: {"name": "Easy", "elo": 1320},
    3: {"name": "Medium", "elo": 1700},
    4: {"name": "Hard", "elo": 2100},
    5: {"name": "Master", "elo": None},
}

_slots = asyncio.Semaphore(int(os.environ.get("BOT_CONCURRENCY", "2")))


class EngineUnavailable(Exception):
    pass


def engine_path() -> str | None:
    env = os.environ.get("STOCKFISH_PATH")
    candidates = [env] if env else []
    candidates += [str(ENGINE_DIR / "stockfish.exe"), str(ENGINE_DIR / "stockfish"), shutil.which("stockfish")]
    return next((c for c in candidates if c and Path(c).is_file()), None)


def available() -> bool:
    return engine_path() is not None


def label(level: int) -> str:
    return f"Stockfish · {LEVELS[level]['name']}"


def display_rating(level: int) -> int | None:
    return LEVELS[level]["elo"]


def think_time_s(remaining_ms: int) -> float:
    """Spend a small slice of the bot's clock, never more than 1.5s and never zero."""
    return max(0.1, min(1.5, remaining_ms / 1000 / 40))


async def _open() -> chess.engine.UciProtocol:
    path = engine_path()
    if not path:
        raise EngineUnavailable("Stockfish is not installed (see README)")
    _, engine = await chess.engine.popen_uci(path)
    return engine


async def choose_move(board: chess.Board, level: int, remaining_ms: int) -> str:
    cfg = LEVELS[level]
    # Beginners sometimes just play a random legal move, like a person who doesn't see the threat.
    if random.random() < cfg.get("blunder", 0):
        return random.choice(list(board.legal_moves)).uci()
    async with _slots:
        engine = await _open()
        try:
            opts: dict = {}
            if "skill" in cfg:
                opts["Skill Level"] = cfg["skill"]
            if cfg["elo"] is not None and "skill" not in cfg:
                opts["UCI_LimitStrength"] = True
                opts["UCI_Elo"] = max(1320, cfg["elo"])
            if opts:
                await engine.configure(opts)
            limit = (chess.engine.Limit(depth=cfg["depth"]) if "depth" in cfg
                     else chess.engine.Limit(time=think_time_s(remaining_ms)))
            result = await engine.play(board, limit)
            return result.move.uci()
        finally:
            try:
                await engine.quit()
            except Exception:
                engine.close()


async def score_for_side_to_move(board: chess.Board, pov_white: bool) -> int:
    """Quick evaluation in centipawns from the given side's point of view."""
    async with _slots:
        engine = await _open()
        try:
            info = await engine.analyse(board, chess.engine.Limit(time=0.2))
            return info["score"].pov(chess.WHITE if pov_white else chess.BLACK).score(mate_score=10_000)
        finally:
            try:
                await engine.quit()
            except Exception:
                engine.close()
