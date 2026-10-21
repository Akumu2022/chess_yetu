"""Game review endpoints. Only adult games are exposed; the kids section has its own tables."""
from fastapi import APIRouter, HTTPException

from . import analysis, bot
from .db import GameAnalysis, GameRecord, SessionLocal, User

router = APIRouter(tags=["review"])


def _names(db, rec: GameRecord) -> dict:
    out = {}
    for color, uid in (("white", rec.white_id), ("black", rec.black_id)):
        user = db.get(User, uid) if uid else None
        out[color] = user.username if user else "Guest"
    return out


@router.get("/review/{game_id}")
def get_review(game_id: str):
    with SessionLocal() as db:
        rec = db.get(GameRecord, game_id)
        if not rec:
            raise HTTPException(404, "No finished game with that link")
        cached = db.get(GameAnalysis, game_id)
        return {"id": rec.id, "moves": rec.moves, "result": rec.result, "reason": rec.reason, "rated": rec.rated,
                "players": _names(db, rec), "initial_ms": rec.initial_ms, "increment_ms": rec.increment_ms,
                "played_at": rec.played_at.isoformat(),
                "analysis": cached.data if cached else None, "engine": bot.available()}


@router.post("/review/{game_id}/analyze")
async def analyze(game_id: str):
    with SessionLocal() as db:
        rec = db.get(GameRecord, game_id)
        if not rec:
            raise HTTPException(404, "No finished game with that link")
        cached = db.get(GameAnalysis, game_id)
        if cached:
            return cached.data
        moves = list(rec.moves)
    if not moves:
        raise HTTPException(422, "Nothing to review: no moves were played")
    try:
        data = await analysis.analyse_once(game_id, moves)
    except bot.EngineUnavailable:
        raise HTTPException(503, "Game review is not available on this server")
    with SessionLocal() as db:
        if not db.get(GameAnalysis, game_id):
            db.add(GameAnalysis(game_id=game_id, data=data))
            db.commit()
    return data
