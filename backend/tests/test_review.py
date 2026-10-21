import pytest
from fastapi.testclient import TestClient

from app import analysis, bot, matchmaking
from app.db import GameRecord, SessionLocal
from app.main import app, games

needs_engine = pytest.mark.skipif(not bot.available(), reason="Stockfish not installed")


def test_formulas():
    assert analysis.win_pct(0) == pytest.approx(50)
    assert analysis.win_pct(300) > analysis.win_pct(100) > 50
    assert analysis.accuracy(0) > 99 and analysis.accuracy(40) < 25
    assert analysis.grade(5, True) == "best" and analysis.grade(5, False) == "good"
    assert analysis.grade(12, False) == "inaccuracy" and analysis.grade(25, False) == "mistake"
    assert analysis.grade(35, False) == "blunder"


@pytest.fixture
def client():
    games.clear()
    matchmaking.reset()
    with TestClient(app) as c:
        yield c


def save(game_id, moves, result="0-1"):
    with SessionLocal() as db:
        db.add(GameRecord(id=game_id, moves=moves, result=result, reason="checkmate", rated=False,
                          initial_ms=60000, increment_ms=0))
        db.commit()


def test_unknown_or_empty_games(client):
    assert client.get("/review/nope").status_code == 404
    assert client.post("/review/nope/analyze").status_code == 404
    save("empty01", [], "1/2-1/2")
    assert client.post("/review/empty01/analyze").status_code == 422


@needs_engine
def test_fools_mate_blunder_is_flagged_and_cached(client):
    save("fool001", ["f2f3", "e7e5", "g2g4", "d8h4"])  # 2.g4?? allows Qh4#
    r = client.get("/review/fool001").json()
    assert r["analysis"] is None and r["players"] == {"white": "Guest", "black": "Guest"}
    a = client.post("/review/fool001/analyze").json()
    assert len(a["evals"]) == 5 and a["evals"][-1] < -900  # black mates at the end
    g4 = a["moves"][2]
    assert g4["san"] == "g4" and g4["cls"] == "blunder" and g4["best_san"]
    assert a["moves"][3]["san"] == "Qh4#" and a["moves"][3]["cls"] in ("best", "good")
    assert a["accuracy"]["white"] < a["accuracy"]["black"]
    # stored: the second request is served from the database
    assert client.get("/review/fool001").json()["analysis"]["accuracy"] == a["accuracy"]
