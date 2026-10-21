import pytest

from app import persistence
from app.db import LiveGame, SessionLocal, init_db
from app.game import Game
from app.main import _finalize, games


@pytest.fixture(autouse=True)
def tables():
    init_db()
    with SessionLocal() as db:
        db.query(LiveGame).delete()
        db.commit()


def make_game(gid="pers01", signed_in=True):
    g = Game(id=gid, initial_ms=300_000, increment_ms=2000)
    g.add_player(7 if signed_in else None, "ann", 1500)
    g.add_player(8 if signed_in else None, "ben", 1600)
    g.play("white", 1, "e2e4")
    g.play("black", 2, "e7e5")
    return g


def test_a_game_in_progress_survives_a_restart():
    games.clear()
    persistence.reset()
    g = make_game()
    games[g.id] = g
    assert persistence.flush(games) == 1
    assert persistence.flush(games) == 0  # unchanged: nothing to write

    games.clear()  # the server restarts
    persistence.reset()
    assert persistence.restore(games) == 1
    r = games["pers01"]
    assert r.moves == ["e2e4", "e7e5"] and r.board.fen() == g.board.fen()
    assert r.status == "active" and r.turn == "white"
    assert r.tokens == g.tokens and r.user_ids == {"white": 7, "black": 8}
    assert r.players["black"]["name"] == "ben" and r.increment_ms == 2000
    r.play("white", 3, "g1f3")  # and it can carry on
    assert r.seq == 3
    persistence.flush(games)
    with SessionLocal() as db:
        assert db.get(LiveGame, "pers01").data["moves"] == ["e2e4", "e7e5", "g1f3"]


def test_waiting_games_are_kept_and_finished_games_are_forgotten():
    games.clear()
    persistence.reset()
    waiting = Game(id="pers02", initial_ms=60_000, increment_ms=0)
    waiting.add_player()
    games[waiting.id] = waiting
    persistence.flush(games)
    games.clear()
    persistence.reset()
    assert persistence.restore(games) == 1 and games["pers02"].status == "waiting"

    done = make_game("pers03", signed_in=False)
    games[done.id] = done
    persistence.flush(games)
    done.resign("black")
    _finalize(done)
    persistence.flush(games)
    with SessionLocal() as db:
        assert db.get(LiveGame, "pers03") is None  # no longer live
    persistence._over_since["pers03"] = -10_000
    assert persistence.evict_finished(games) == 1 and "pers03" not in games
    games.clear()
    persistence.reset()
