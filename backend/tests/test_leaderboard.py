from fastapi.testclient import TestClient

from app import leaderboard
from app.db import GameRecord, SessionLocal, User
from app.main import app


def make_user(name, rating, games):
    with SessionLocal() as db:
        u = User(username=name, pw_hash="x", rating=rating, games=games)
        db.add(u)
        db.commit()
        return u.id


def test_ranking_orders_by_rating_and_hides_unproven_players():
    with TestClient(app) as c:
        make_user("lb_top", 1900, 12)
        make_user("lb_mid", 1650, 8)
        make_user("lb_new", 2400, leaderboard.MIN_GAMES - 1)  # too few games to be ranked
        r = c.get("/leaderboard?limit=100").json()
        names = [p["username"] for p in r["players"]]
        assert "lb_new" not in names
        assert names.index("lb_top") < names.index("lb_mid")
        assert [p["rank"] for p in r["players"]] == list(range(1, len(names) + 1))
        assert set(r["players"][0]) == {"rank", "username", "rating", "games"}  # nothing private


def test_profile_record_rank_and_recent_games():
    with TestClient(app) as c:
        a = make_user("pf_ann", 1700, 6)
        b = make_user("pf_ben", 1600, 6)
        with SessionLocal() as db:
            for i, res in enumerate(["1-0", "1-0", "0-1", "1/2-1/2"]):
                db.add(GameRecord(id=f"pf{i}", white_id=a, black_id=b, moves=["e2e4"], result=res,
                                  reason="checkmate", rated=True, initial_ms=1, increment_ms=0))
            db.commit()
        p = c.get("/players/PF_ANN").json()  # case-insensitive
        assert p["record"] == {"won": 2, "drawn": 1, "lost": 1}
        assert p["rank"] is not None and len(p["recent"]) == 4
        assert p["recent"][0]["opponent"] == "pf_ben"
        q = c.get("/players/pf_ben").json()
        assert q["record"] == {"won": 1, "drawn": 1, "lost": 2}
        assert c.get("/players/nobody_here").status_code == 404
