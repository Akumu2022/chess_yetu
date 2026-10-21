import pytest
from fastapi.testclient import TestClient

from app.game import Game, GameError
from app.main import app, games


def make_game(minutes=1, inc=0) -> Game:
    g = Game(id="t", initial_ms=minutes * 60_000, increment_ms=inc * 1000)
    g.add_player()
    g.add_player()
    return g


def test_fools_mate():
    g = make_game()
    for i, (c, m) in enumerate([("white", "f2f3"), ("black", "e7e5"),
                                ("white", "g2g4"), ("black", "d8h4")], start=1):
        g.play(c, i, m)
    assert g.status == "over" and g.result == "0-1" and g.reason == "checkmate"


def test_rejects_wrong_turn_illegal_and_bad_seq():
    g = make_game()
    with pytest.raises(GameError) as e:
        g.play("black", 1, "e7e5")
    assert e.value.code == "not_your_turn"
    with pytest.raises(GameError) as e:
        g.play("white", 1, "e2e5")
    assert e.value.code == "illegal_move"
    g.play("white", 1, "e2e4")
    with pytest.raises(GameError) as e:  # duplicate of an already-applied seq
        g.play("black", 1, "e7e5")
    assert e.value.code == "bad_seq"


def test_increment_added():
    g = make_game(minutes=1, inc=2)
    g.play("white", 1, "e2e4")
    assert g.clocks["white"] > 60_000


def test_timeout():
    g = make_game()
    g.clocks["white"] = 0
    assert g.check_flag() and g.result == "0-1" and g.reason == "timeout"


def test_draw_by_agreement_and_resign():
    g = make_game()
    assert g.offer_draw("white") is False
    assert g.offer_draw("black") is True and g.result == "1/2-1/2"
    g2 = make_game()
    g2.resign("white")
    assert g2.result == "0-1"


def test_websocket_play_and_resync():
    games.clear()
    with TestClient(app) as client:
        a = client.post("/games", json={"minutes": 5, "increment": 3}).json()
        b = client.post(f"/games/{a['game_id']}/join").json()
        url = f"/ws/games/{a['game_id']}"
        with client.websocket_connect(url) as wa, client.websocket_connect(url) as wb:
            wa.send_json({"type": "hello", "v": 1, "token": a["token"]})
            assert wa.receive_json()["type"] == "resync"
            wb.send_json({"type": "hello", "v": 1, "token": b["token"]})
            assert wb.receive_json()["you"] == "black"
            wa.send_json({"type": "move", "seq": 1, "move": "e2e4"})
            # drain until move_made (opponent_status messages may interleave)
            while (m := wb.receive_json())["type"] != "move_made":
                pass
            assert m["move"] == "e2e4" and m["seq"] == 1
        # reconnect as black: resync must contain the move we missed
        with client.websocket_connect(url) as wb2:
            wb2.send_json({"type": "hello", "v": 1, "token": b["token"]})
            r = wb2.receive_json()
            assert r["type"] == "resync" and r["moves"] == ["e2e4"]


def test_bad_token_rejected():
    games.clear()
    with TestClient(app) as client:
        a = client.post("/games", json={}).json()
        with client.websocket_connect(f"/ws/games/{a['game_id']}") as w:
            w.send_json({"type": "hello", "v": 1, "token": "nope"})
            assert w.receive_json()["code"] == "bad_token"
