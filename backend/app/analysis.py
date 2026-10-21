"""Post-game review: Stockfish scores every position, then each move is graded by how much winning chance it cost.

Win-chance and accuracy formulas follow the ones Lichess publishes (open source), so grades feel familiar.
"""
import asyncio
import math

import chess
import chess.engine

from . import bot

MATE_CP = 10_000
CP_CLAMP = 1000  # shown evals are clamped; the graph does not need more
_slot = asyncio.Semaphore(1)  # one review at a time; they are heavy
_inflight: dict[str, asyncio.Future] = {}


def win_pct(cp: float) -> float:
    """Chance of winning (0..100) for the side the score favours."""
    cp = max(-CP_CLAMP, min(CP_CLAMP, cp))
    return 50 + 50 * (2 / (1 + math.exp(-0.00368208 * cp)) - 1)


def accuracy(loss: float) -> float:
    return max(0.0, min(100.0, 103.1668 * math.exp(-0.04354 * loss) - 3.1668))


def grade(loss: float, best: bool) -> str:
    if loss >= 30:
        return "blunder"
    if loss >= 20:
        return "mistake"
    if loss >= 10:
        return "inaccuracy"
    return "best" if best else "good"


def _terminal_cp(board: chess.Board) -> int:
    """Score (white's view) of a finished position."""
    if board.is_checkmate():
        return -MATE_CP if board.turn == chess.WHITE else MATE_CP
    return 0


def _time_per_position(plies: int) -> float:
    return 0.12 if plies <= 100 else 0.06


async def analyse_moves(moves: list[str]) -> dict:
    """Score every position, then grade each move."""
    if not bot.available():
        raise bot.EngineUnavailable("Stockfish is not installed")
    board = chess.Board()
    positions: list[chess.Board] = [board.copy()]
    for uci in moves:
        board.push_uci(uci)
        positions.append(board.copy())

    limit = chess.engine.Limit(time=_time_per_position(len(moves)))
    evals: list[int] = []
    best: list[str | None] = []
    async with _slot:
        _, engine = await chess.engine.popen_uci(bot.engine_path())
        try:
            for pos in positions:
                if pos.is_game_over(claim_draw=False):
                    evals.append(_terminal_cp(pos))
                    best.append(None)
                    continue
                info = await engine.analyse(pos, limit)
                evals.append(info["score"].white().score(mate_score=MATE_CP))
                pv = info.get("pv")
                best.append(pv[0].uci() if pv else None)
        finally:
            try:
                await engine.quit()
            except Exception:
                engine.close()

    graded = []
    totals: dict[str, list[float]] = {"white": [], "black": []}
    counts = {c: {"best": 0, "good": 0, "inaccuracy": 0, "mistake": 0, "blunder": 0} for c in totals}
    replay = chess.Board()
    for i, uci in enumerate(moves):
        color = "white" if i % 2 == 0 else "black"
        sign = 1 if color == "white" else -1
        loss = max(0.0, win_pct(sign * evals[i]) - win_pct(sign * evals[i + 1]))
        cls = grade(loss, best[i] == uci)
        counts[color][cls] += 1
        totals[color].append(accuracy(loss))
        entry = {"uci": uci, "san": replay.san(chess.Move.from_uci(uci)), "cls": cls,
                 "loss": round(loss, 1), "best": best[i], "best_san": None}
        if best[i] and best[i] != uci:
            entry["best_san"] = replay.san(chess.Move.from_uci(best[i]))
        graded.append(entry)
        replay.push_uci(uci)
    avg = {c: round(sum(v) / len(v), 1) if v else None for c, v in totals.items()}
    return {
        "evals": [max(-CP_CLAMP, min(CP_CLAMP, e)) for e in evals],
        "moves": graded,
        "accuracy": avg,
        "counts": counts,
    }


async def analyse_once(game_id: str, moves: list[str]) -> dict:
    """Share one running analysis between callers who ask for the same game."""
    fut = _inflight.get(game_id)
    if fut:
        return await asyncio.shield(fut)
    fut = asyncio.get_running_loop().create_future()
    _inflight[game_id] = fut
    try:
        result = await analyse_moves(moves)
        fut.set_result(result)
        return result
    except BaseException as e:
        fut.set_exception(e)
        fut.exception()  # mark retrieved so a lone caller does not log "never retrieved"
        raise
    finally:
        _inflight.pop(game_id, None)
