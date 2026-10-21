import chess
import pytest
from fastapi.testclient import TestClient

from app import kids, matchmaking, mates, puzzles
from app.db import PuzzleStreak, SessionLocal
from app.main import app, games

from tests.test_kids import add_child, parent_with_pin, signup

pytestmark = pytest.mark.skipif(not puzzles.PUZZLES, reason="no puzzles generated")


@pytest.fixture
def client():
    games.clear()
    matchmaking.reset()
    kids._pin_state.clear()
    with TestClient(app) as c:
        yield c


def solve(client, h, puzzle):
    """Play a puzzle the way the page does: send the moves so far, get the defender's reply back."""
    board = chess.Board(puzzle["fen"])
    played = []
    while True:
        mv = mates.forcing_moves(board, puzzle["depth"] - len(played))[0]
        played.append(mv.uci())
        r = client.post(f"/puzzles/{puzzle['id']}/move", json={"played": played}, headers=h).json()
        if r["status"] != "continue":
            return r
        board.push(mv)
        board.push(chess.Move.from_uci(r["reply"]))


def test_every_puzzle_is_a_real_forced_mate():
    for p in puzzles.PUZZLES:
        b = chess.Board(p["fen"])
        assert mates.forcing_moves(b, p["depth"]), p["fen"]
        if p["depth"] == 2:
            assert not mates.mates_now(b), p["fen"]  # it must not be a mate in 1 in disguise


def test_guests_cannot_play(client):
    assert client.get("/puzzles/next").status_code == 401


def test_solution_is_never_sent_and_wrong_moves_are_rejected(client):
    h = signup(client, "pz1")
    r = client.get("/puzzles/next", headers=h).json()
    p = r["puzzle"]
    assert set(p) == {"id", "fen", "depth", "theme", "to_move"}
    b = chess.Board(p["fen"])
    good = {m.uci() for m in mates.forcing_moves(b, p["depth"])}
    bad = next(m.uci() for m in b.legal_moves if m.uci() not in good)
    assert client.post(f"/puzzles/{p['id']}/move", json={"played": [bad]}, headers=h).json()["status"] == "wrong"
    assert client.post(f"/puzzles/{p['id']}/move", json={"played": ["zzzz"]}, headers=h).json()["status"] == "wrong"


def test_daily_limit_and_streak(client):
    h = signup(client, "pz2")
    for i in range(puzzles.DAILY_LIMIT):
        nxt = client.get("/puzzles/next", headers=h).json()
        assert "puzzle" in nxt and nxt["solved_today"] == i
        res = solve(client, h, puzzles.BY_ID[nxt["puzzle"]["id"]])
        assert res["status"] == "solved"
    assert res["solved_today"] == puzzles.DAILY_LIMIT and res["streak"]["current"] == 1
    done = client.get("/puzzles/next", headers=h).json()
    assert done["limit_reached"] is True
    # and a fourth puzzle can't be sneaked in by id
    r = client.post(f"/puzzles/{puzzles.PUZZLES[-1]['id']}/move", json={"played": ["a2a3"]}, headers=h)
    assert r.status_code == 403


def test_streak_rules():
    """Consecutive days build; one missed day is forgiven by a freeze; two missed days reset."""
    today = puzzles._today()
    yday, two, three = (puzzles._day_before(today, n) for n in (1, 2, 3))
    s = PuzzleStreak(owner_kind="user", owner_id=1, current=5, best=5, last_day=yday, freezes=1)
    assert puzzles._streak_view(s)["current"] == 5
    s.last_day = two
    assert puzzles._streak_view(s)["current"] == 5  # forgivable
    s.freezes = 0
    assert puzzles._streak_view(s)["current"] == 0
    s.freezes = 1
    s.last_day = three
    assert puzzles._streak_view(s)["current"] == 0


def test_a_kid_plays_puzzles_and_deleting_the_child_erases_progress(client):
    h = parent_with_pin(client, "pz3mama")
    c = add_child(client, h)
    kid = {"Authorization": "Bearer " + client.post(f"/kids/children/{c['id']}/session", headers=h).json()["token"]}
    nxt = client.get("/puzzles/next", headers=kid).json()
    assert solve(client, kid, puzzles.BY_ID[nxt["puzzle"]["id"]])["status"] == "solved"
    assert client.get("/puzzles/today", headers=kid).json()["solved_today"] == 1
    assert client.delete(f"/kids/children/{c['id']}", headers=h).status_code == 200
    with SessionLocal() as db:
        assert db.query(puzzles.PuzzleSolve).filter_by(owner_kind="child", owner_id=c["id"]).count() == 0
        assert db.get(PuzzleStreak, ("child", c["id"])) is None
