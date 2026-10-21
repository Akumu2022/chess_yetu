"""Public ranking and player profiles. Adults only: kids are never listed anywhere public."""
from fastapi import APIRouter, HTTPException, Query
from sqlalchemy import func, or_

from .db import GameRecord, SessionLocal, User

router = APIRouter(tags=["leaderboard"])

MIN_GAMES = 5  # a rating needs a few games behind it before it is ranked


def _ranked(db):
    return db.query(User).filter(User.games >= MIN_GAMES)


@router.get("/leaderboard")
def leaderboard(limit: int = Query(50, ge=1, le=100)):
    with SessionLocal() as db:
        rows = _ranked(db).order_by(User.rating.desc(), User.games.desc(), User.id).limit(limit).all()
        return {"min_games": MIN_GAMES,
                "players": [{"rank": i, "username": u.username, "rating": round(u.rating), "games": u.games}
                            for i, u in enumerate(rows, 1)]}


@router.get("/players/{username}")
def profile(username: str):
    with SessionLocal() as db:
        user = db.query(User).filter(func.lower(User.username) == username.lower()).first()
        if not user:
            raise HTTPException(404, "No such player")
        rank = None
        if user.games >= MIN_GAMES:
            rank = 1 + _ranked(db).filter(User.rating > user.rating).count()
        mine = or_(GameRecord.white_id == user.id, GameRecord.black_id == user.id)
        recs = (db.query(GameRecord).filter(mine).filter(GameRecord.rated.is_(True))
                .order_by(GameRecord.played_at.desc()).limit(500).all())
        won = drawn = lost = 0
        for r in recs:
            if r.result == "1/2-1/2":
                drawn += 1
            elif (r.result == "1-0") == (r.white_id == user.id):
                won += 1
            else:
                lost += 1
        recent = []
        for r in recs[:10]:
            color = "white" if r.white_id == user.id else "black"
            opp_id = r.black_id if color == "white" else r.white_id
            opp = db.get(User, opp_id) if opp_id else None
            outcome = "draw" if r.result == "1/2-1/2" else ("win" if (r.result == "1-0") == (color == "white") else "loss")
            recent.append({"id": r.id, "opponent": opp.username if opp else "Guest", "color": color,
                           "outcome": outcome, "moves": len(r.moves), "played_at": r.played_at.isoformat()})
        return {"username": user.username, "rating": round(user.rating), "games": user.games, "rank": rank,
                "record": {"won": won, "drawn": drawn, "lost": lost}, "recent": recent}
