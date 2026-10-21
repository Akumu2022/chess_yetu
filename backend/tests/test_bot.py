import asyncio

import chess
import pytest
from fastapi.testclient import TestClient

from app import bot, matchmaking
from app.main import app, games

needs_engine = pytest.mark.skipif(not bot.available(), reason="Stockfish not installed")


@pytest.fixture
def client():
    games.clear()
    matchmaking.reset()
    with TestClient(app) as c:
        yield c


def next_of(ws, *types, limit=40):
    for _ in range(limit):
        m = ws.receive_json()
        if m["type"] in types:
            return m
    raise AssertionError(f"never saw {types}")


@needs_engine
@pytest.mark.parametrize("level", sorted(bot.LEVELS))
def test_every_level_returns_a_legal_move(level):
    board = chess.Board()
    uci = asyncio.run(bot.choose_move(board, level, remaining_ms=4000))
    assert chess.Move.from_uci(uci) in board.legal_moves


@needs_engine
def test_bot_replies_to_a_human_move(client):
    g = client.post("/games/ai", json={"level": 2, "color": "white", "minutes": 5, "increment": 0}).json()
    with client.websocket_connect(f"/ws/games/{g['game_id']}") as ws:
        ws.send_json({"type": "hello", "v": 1, "token": g["token"]})
        resync = ws.receive_json()
        assert resync["vs_bot"] is True and resync["players"]["black"]["name"].startswith("Stockfish")
        assert resync["rated"] is False
        ws.send_json({"type": "move", "seq": 1, "move": "e2e4"})
        assert next_of(ws, "move_made")["seq"] == 1
        reply = next_of(ws, "move_made")
        assert reply["seq"] == 2
        board = chess.Board()
        board.push_uci("e2e4")
        assert chess.Move.from_uci(reply["move"]) in board.legal_moves
        ws.send_json({"type": "resign"})
        over = next_of(ws, "game_over")
        assert over["result"] == "0-1" and over["rating_change"] is None


@needs_engine
def test_bot_opens_when_it_plays_white(client):
    g = client.post("/games/ai", json={"level": 1, "color": "black"}).json()
    assert g["color"] == "black"
    with client.websocket_connect(f"/ws/games/{g['game_id']}") as ws:
        ws.send_json({"type": "hello", "v": 1, "token": g["token"]})
        assert ws.receive_json()["type"] == "resync"
        first = next_of(ws, "move_made")
        assert first["seq"] == 1
        assert chess.Move.from_uci(first["move"]) in chess.Board().legal_moves


@needs_engine
def test_bot_declines_an_early_draw(client):
    g = client.post("/games/ai", json={"level": 2, "color": "white"}).json()
    with client.websocket_connect(f"/ws/games/{g['game_id']}") as ws:
        ws.send_json({"type": "hello", "v": 1, "token": g["token"]})
        ws.receive_json()
        ws.send_json({"type": "draw"})
        assert next_of(ws, "draw_declined")["type"] == "draw_declined"


def test_bot_game_unavailable_without_engine(client, monkeypatch):
    monkeypatch.setattr(bot, "available", lambda: False)
    r = client.post("/games/ai", json={})
    assert r.status_code == 503


def test_rejects_bad_level(client):
    assert client.post("/games/ai", json={"level": 9}).status_code == 422
