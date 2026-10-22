import time

import pytest
from fastapi.testclient import TestClient

from app import matchmaking
from app.main import app, games


@pytest.fixture
def client():
    games.clear()
    matchmaking.reset()
    with TestClient(app) as c:
        yield c


def signup(client, name):
    r = client.post("/auth/register", json={"username": name, "password": "password123"})
    assert r.status_code == 200, r.text
    return {"Authorization": f"Bearer {r.json()['token']}"}


def play_fools_mate(client, white, black, gid):
    """white = (headers, token), black likewise. Black wins by checkmate."""
    url = f"/ws/games/{gid}"
    with client.websocket_connect(url) as wa, client.websocket_connect(url) as wb:
        wa.send_json({"type": "hello", "v": 1, "token": white[1]})
        wb.send_json({"type": "hello", "v": 1, "token": black[1]})
        for ws, seq, mv in [(wa, 1, "f2f3"), (wb, 2, "e7e5"), (wa, 3, "g2g4"), (wb, 4, "d8h4")]:
            ws.send_json({"type": "move", "seq": seq, "move": mv})
        while (m := wa.receive_json())["type"] != "game_over":
            pass
        return m


def test_register_login_and_duplicates(client):
    h = signup(client, "Wanjiru")
    assert client.get("/me", headers=h).json()["rating"] == 1500
    assert client.post("/auth/register", json={"username": "wanjiru", "password": "password123"}).status_code == 409
    assert client.post("/auth/login", json={"username": "Wanjiru", "password": "wrongpass1"}).status_code == 401
    assert client.post("/auth/login", json={"username": "Wanjiru", "password": "password123"}).status_code == 200
    assert client.get("/me").status_code == 401
    assert client.post("/auth/register", json={"username": "a b", "password": "password123"}).status_code == 422


def test_rated_game_updates_ratings_and_history(client):
    ha, hb = signup(client, "alice"), signup(client, "brian")
    g = client.post("/games", json={"minutes": 5, "increment": 0}, headers=ha).json()
    j = client.post(f"/games/{g['game_id']}/join", headers=hb).json()
    assert g["color"] == "white" and j["color"] == "black"

    over = play_fools_mate(client, (ha, g["token"]), (hb, j["token"]), g["game_id"])
    assert over["result"] == "0-1"
    assert over["rating_change"]["black"] > 0 > over["rating_change"]["white"]

    assert client.get("/me", headers=ha).json()["rating"] < 1500
    assert client.get("/me", headers=hb).json()["rating"] > 1500
    hist = client.get("/me/games", headers=hb).json()
    assert len(hist) == 1 and hist[0]["color"] == "black" and hist[0]["delta"] > 0


def test_guest_game_is_unrated(client):
    ha = signup(client, "carol")
    g = client.post("/games", json={}, headers=ha).json()
    j = client.post(f"/games/{g['game_id']}/join").json()  # guest opponent
    over = play_fools_mate(client, (ha, g["token"]), ({}, j["token"]), g["game_id"])
    assert over["rating_change"] is None
    assert client.get("/me", headers=ha).json()["rating"] == 1500


def test_cannot_play_yourself(client):
    h = signup(client, "dave")
    g = client.post("/games", json={}, headers=h).json()
    # Opening your own game link gives you your own seat back; it never makes you your own opponent.
    r = client.post(f"/games/{g['game_id']}/join", headers=h)
    assert r.status_code == 200 and r.json()["color"] == g["color"] and r.json()["token"] == g["token"]
    assert client.get(f"/games/{g['game_id']}").json()["status"] == "waiting"


def test_queue_pairs_two_players_with_matching_control(client):
    ha, hb, hc = signup(client, "erin"), signup(client, "femi"), signup(client, "gita")
    assert client.post("/queue", json={"minutes": 5, "increment": 3}, headers=ha).json()["status"] == "waiting"
    assert client.get("/queue", headers=ha).json()["status"] == "waiting"
    # different time control must not pair
    assert client.post("/queue", json={"minutes": 10, "increment": 0}, headers=hc).json()["status"] == "waiting"
    r = client.post("/queue", json={"minutes": 5, "increment": 3}, headers=hb).json()
    assert r["status"] == "matched"
    polled = client.get("/queue", headers=ha).json()
    assert polled["status"] == "matched" and polled["seat"]["game_id"] == r["seat"]["game_id"]
    assert {polled["seat"]["color"], r["seat"]["color"]} == {"white", "black"}
    assert client.get("/queue", headers=ha).json()["status"] == "idle"  # consumed


def test_queue_respects_rating_window(client):
    ha, hb = signup(client, "hana"), signup(client, "ivan")
    client.post("/queue", json={"minutes": 5, "increment": 0}, headers=ha)
    matchmaking.queue[next(iter(matchmaking.queue))].rating = 2200  # far apart
    assert client.post("/queue", json={"minutes": 5, "increment": 0}, headers=hb).json()["status"] == "waiting"


def test_same_account_cannot_queue_twice(client):
    h = signup(client, "judy")
    assert client.post("/queue", json={"minutes": 5, "increment": 0}, headers=h).json() == {"status": "waiting"}
    client.get("/queue", headers=h)  # first tab keeps polling
    second = client.post("/queue", json={"minutes": 5, "increment": 0}, headers=h).json()
    assert second["status"] == "waiting" and second["already_searching"] is True


def test_queue_never_pairs_with_a_ghost(client):
    ha, hb = signup(client, "kito"), signup(client, "lulu")
    client.post("/queue", json={"minutes": 5, "increment": 0}, headers=ha)
    matchmaking.queue[next(iter(matchmaking.queue))].last_seen -= 10  # tab closed 10s ago
    assert client.post("/queue", json={"minutes": 5, "increment": 0}, headers=hb).json()["status"] == "waiting"


def test_sign_in_lasts_thirty_days(client):
    import jwt as pyjwt

    from app import auth

    r = client.post("/auth/register", json={"username": "daylong", "password": "password123"})
    claims = pyjwt.decode(r.json()["token"], auth.SECRET, algorithms=["HS256"])
    assert 29 * 86400 < claims["exp"] - time.time() <= 30 * 86400
