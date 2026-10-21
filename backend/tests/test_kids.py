import re
from datetime import datetime

import pytest
from fastapi.testclient import TestClient

from app import bot, kids, matchmaking
from app.db import KidGameRecord, SessionLocal
from app.main import app, games

needs_engine = pytest.mark.skipif(not bot.available(), reason="Stockfish not installed")
YEAR = datetime.now(kids.EAT).year


@pytest.fixture
def client():
    games.clear()
    matchmaking.reset()
    kids._pin_state.clear()
    with TestClient(app) as c:
        yield c


def signup(client, name):
    r = client.post("/auth/register", json={"username": name, "password": "password123"})
    assert r.status_code == 200, r.text
    return {"Authorization": f"Bearer {r.json()['token']}"}


def parent_with_pin(client, name, pin="1234"):
    h = signup(client, name)
    assert client.put("/kids/pin", json={"pin": pin}, headers=h).status_code == 200
    return h


def add_child(client, h, age=8):
    r = client.post("/kids/children", json={"birth_year": YEAR - age, "consent": True}, headers=h)
    assert r.status_code == 200, r.text
    return r.json()


def kid_session(client, h, child):
    r = client.post(f"/kids/children/{child['id']}/session", headers=h)
    assert r.status_code == 200, r.text
    return {"Authorization": f"Bearer {r.json()['token']}"}


def hello(ws, token):
    ws.send_json({"type": "hello", "v": 1, "token": token})
    return ws.receive_json()


def drain_until(ws, kind, limit=40):
    for _ in range(limit):
        m = ws.receive_json()
        if m["type"] == kind:
            return m
    raise AssertionError(f"never saw {kind}")


# ---- creating children ----------------------------------------------------------

def test_child_needs_consent_and_right_age(client):
    h = signup(client, "mama1")
    assert client.post("/kids/children", json={"birth_year": YEAR - 8}, headers=h).status_code == 422
    assert client.post("/kids/children", json={"birth_year": YEAR - 8, "consent": False}, headers=h).status_code == 422
    for age in (4, 14, 30):
        assert client.post("/kids/children", json={"birth_year": YEAR - age, "consent": True}, headers=h).status_code == 422
    for age in (5, 13):
        assert client.post("/kids/children", json={"birth_year": YEAR - age, "consent": True}, headers=h).status_code == 200
    assert client.post("/kids/children", json={"birth_year": YEAR - 8, "consent": True}).status_code == 401


def test_child_gets_generated_nickname_and_minimal_data(client):
    h = signup(client, "mama2")
    child = add_child(client, h)
    assert re.fullmatch(r"[A-Z][a-z]+[A-Z][a-z]+\d{3}", child["nickname"])
    assert "mama2" not in str(child)  # nothing about the parent leaks into the child's profile
    assert child["rating"] == 1500 and child["minutes_left"] == 60


def test_parents_only_see_and_control_their_own_children(client):
    a, b = signup(client, "mama3"), signup(client, "baba3")
    child = add_child(client, a)
    assert client.get("/kids/children", headers=b).json() == []
    assert client.patch(f"/kids/children/{child['id']}", json={"daily_limit_min": 30}, headers=b).status_code == 404
    assert client.delete(f"/kids/children/{child['id']}", headers=b).status_code == 404
    assert client.post(f"/kids/children/{child['id']}/session", headers=b).status_code == 404


# ---- PIN and kid sessions ----------------------------------------------------------

def test_kid_session_needs_a_pin_first(client):
    h = signup(client, "mama4")
    child = add_child(client, h)
    assert client.post(f"/kids/children/{child['id']}/session", headers=h).status_code == 409
    client.put("/kids/pin", json={"pin": "4321"}, headers=h)
    assert client.post(f"/kids/children/{child['id']}/session", headers=h).status_code == 200


def test_pin_rules(client):
    h = signup(client, "mama5")
    assert client.put("/kids/pin", json={"pin": "12"}, headers=h).status_code == 422
    assert client.put("/kids/pin", json={"pin": "abcd"}, headers=h).status_code == 422
    assert client.put("/kids/pin", json={"pin": "1234"}, headers=h).status_code == 200
    # changing it needs the old one
    assert client.put("/kids/pin", json={"pin": "9999"}, headers=h).status_code == 422
    assert client.put("/kids/pin", json={"pin": "9999", "current": "0000"}, headers=h).status_code == 403
    assert client.put("/kids/pin", json={"pin": "9999", "current": "1234"}, headers=h).status_code == 200


def test_kid_cannot_use_any_adult_feature(client):
    h = parent_with_pin(client, "mama6")
    kid = kid_session(client, h, add_child(client, h))
    assert client.get("/me", headers=kid).status_code == 403
    assert client.get("/me/games", headers=kid).status_code == 403
    assert client.post("/queue", json={}, headers=kid).status_code == 403
    assert client.post("/games", json={}, headers=kid).status_code == 403
    assert client.post("/games/ai", json={}, headers=kid).status_code == 403
    adult_game = client.post("/games", json={}).json()
    assert client.post(f"/games/{adult_game['game_id']}/join", headers=kid).status_code == 403
    assert client.get("/kids/children", headers=kid).status_code == 403  # parent area: refused outright


def test_adult_cannot_use_kid_endpoints(client):
    h = parent_with_pin(client, "mama7")
    assert client.get("/kids/me", headers=h).status_code == 401
    assert client.post("/kids/queue", json={}, headers=h).status_code == 401
    assert client.post("/kids/games/ai", json={}, headers=h).status_code == 401


def test_leaving_kids_mode_needs_the_parent_pin_and_locks_after_guessing(client):
    h = parent_with_pin(client, "mama8", "2468")
    kid = kid_session(client, h, add_child(client, h))
    for _ in range(4):
        assert client.post("/kids/exit", json={"pin": "0000"}, headers=kid).status_code == 403
    assert client.post("/kids/exit", json={"pin": "0000"}, headers=kid).status_code == 403  # 5th wrong
    assert client.post("/kids/exit", json={"pin": "2468"}, headers=kid).status_code == 429  # now locked
    kids._pin_state.clear()
    r = client.post("/kids/exit", json={"pin": "2468"}, headers=kid)
    assert r.status_code == 200
    back = {"Authorization": f"Bearer {r.json()['token']}"}
    assert client.get("/me", headers=back).json()["username"] == "mama8"


def test_whoami_tells_the_three_kinds_apart(client):
    h = parent_with_pin(client, "mama9")
    child = add_child(client, h)
    kid = kid_session(client, h, child)
    assert client.get("/whoami").json() == {"kind": "guest"}
    assert client.get("/whoami", headers=h).json()["kind"] == "adult"
    who = client.get("/whoami", headers=kid).json()
    assert who["kind"] == "kid" and who["child"]["nickname"] == child["nickname"]
    assert client.get("/whoami", headers={"Authorization": "Bearer junk"}).status_code == 401


# ---- separate pools ------------------------------------------------------------------

def make_two_kids(client, name):
    h = parent_with_pin(client, name)
    c1, c2 = add_child(client, h), add_child(client, h)
    return h, (c1, kid_session(client, h, c1)), (c2, kid_session(client, h, c2))


def test_kids_match_kids_but_never_adults(client):
    adult = signup(client, "grownup1")
    h, (c1, k1), (c2, k2) = make_two_kids(client, "mama10")
    opts = {"minutes": 10, "increment": 5}
    assert client.post("/queue", json=opts, headers=adult).json()["status"] == "waiting"
    assert client.post("/kids/queue", json=opts, headers=k1).json()["status"] == "waiting"
    # the adult is waiting with the same time control and rating, yet the kid queue stays separate
    assert client.get("/kids/queue", headers=k1).json()["status"] == "waiting"
    r = client.post("/kids/queue", json=opts, headers=k2).json()
    assert r["status"] == "matched"
    polled = client.get("/kids/queue", headers=k1).json()
    assert polled["seat"]["game_id"] == r["seat"]["game_id"]
    assert client.get("/queue", headers=adult).json()["status"] == "waiting"  # adult untouched


def test_kids_game_is_rated_in_the_kids_pool_only(client):
    h, (c1, k1), (c2, k2) = make_two_kids(client, "mama11")
    opts = {"minutes": 10, "increment": 5}
    client.post("/kids/queue", json=opts, headers=k1)
    seats = {}
    r = client.post("/kids/queue", json=opts, headers=k2).json()["seat"]
    seats[r["color"]] = r
    p = client.get("/kids/queue", headers=k1).json()["seat"]
    seats[p["color"]] = p
    gid = r["game_id"]

    with client.websocket_connect(f"/ws/games/{gid}") as ww, client.websocket_connect(f"/ws/games/{gid}") as wb:
        first = hello(ww, seats["white"]["token"])
        assert first["kids"] is True and first["rated"] is True
        hello(wb, seats["black"]["token"])
        for ws, seq, mv in [(ww, 1, "f2f3"), (wb, 2, "e7e5"), (ww, 3, "g2g4"), (wb, 4, "d8h4")]:
            ws.send_json({"type": "move", "seq": seq, "move": mv})
        over = drain_until(ww, "game_over")
    assert over["result"] == "0-1" and over["rating_change"]["black"] > 0 > over["rating_change"]["white"]

    ratings = sorted(c["rating"] for c in client.get("/kids/children", headers=h).json())
    assert ratings[0] < 1500 < ratings[1]
    assert client.get("/me", headers=h).json()["rating"] == 1500  # the parent's own rating is untouched
    # the game went to the kids' tables, not the adult history
    assert client.get("/me/games", headers=h).json() == []
    assert len(client.get(f"/kids/children/{c1['id']}/games", headers=h).json()) == 1


def test_adults_cannot_join_a_kids_game(client):
    h, (c1, k1), (c2, k2) = make_two_kids(client, "mama12")
    client.post("/kids/queue", json={}, headers=k1)
    seat = client.post("/kids/queue", json={}, headers=k2).json()["seat"]
    stranger = signup(client, "stranger1")
    assert client.post(f"/games/{seat['game_id']}/join", headers=stranger).status_code == 403
    assert client.post(f"/games/{seat['game_id']}/join").status_code == 403  # guests too


# ---- preset-only chat -----------------------------------------------------------------

def start_kids_game(client, name):
    h, (c1, k1), (c2, k2) = make_two_kids(client, name)
    client.post("/kids/queue", json={}, headers=k1)
    a = client.post("/kids/queue", json={}, headers=k2).json()["seat"]
    b = client.get("/kids/queue", headers=k1).json()["seat"]
    return a, b


def test_kids_can_only_send_preset_phrases(client):
    a, b = start_kids_game(client, "mama13")
    url = f"/ws/games/{a['game_id']}"
    with client.websocket_connect(url) as wa, client.websocket_connect(url) as wb:
        hello(wa, a["token"])
        hello(wb, b["token"])
        wa.send_json({"type": "say", "id": "gl"})
        said = drain_until(wb, "said")
        assert said == {"type": "said", "by": a["color"], "id": "gl"}
        assert drain_until(wa, "said")["id"] == "gl"  # the sender sees it too

        # free text and unknown ids are rejected, never relayed
        wa.send_json({"type": "say", "text": "call me on 0712345678"})
        assert drain_until(wa, "error")["code"] == "bad_phrase"
        wa.send_json({"type": "say", "id": "gl-or-something-else"})
        assert drain_until(wa, "error")["code"] in ("bad_phrase", "too_fast")

        # and they can't spam
        wb.send_json({"type": "say", "id": "gg"})
        drain_until(wb, "said")
        wb.send_json({"type": "say", "id": "gg"})
        assert drain_until(wb, "error")["code"] == "too_fast"


def test_adult_games_have_no_chat(client):
    g = client.post("/games", json={}).json()
    with client.websocket_connect(f"/ws/games/{g['game_id']}") as ws:
        hello(ws, g["token"])
        ws.send_json({"type": "say", "id": "gg"})
        assert drain_until(ws, "error")["code"] == "chat_disabled"


# ---- time limits and deletion ------------------------------------------------------------

def test_daily_time_limit_blocks_new_games(client):
    h = parent_with_pin(client, "mama14")
    child = add_child(client, h)
    kid = kid_session(client, h, child)
    assert client.patch(f"/kids/children/{child['id']}", json={"daily_limit_min": 10}, headers=h).json()["minutes_left"] == 10
    with SessionLocal() as db:  # a 10-minute game finished earlier today
        db.add(KidGameRecord(id="old1", white_child_id=child["id"], moves=["e2e4"], result="1-0",
                             reason="resignation", duration_s=600))
        db.commit()
    me = client.get("/kids/me", headers=kid).json()
    assert me["minutes_today"] == 10 and me["minutes_left"] == 0
    for path, body in [("/kids/queue", {}), ("/kids/games/ai", {})]:
        r = client.post(path, json=body, headers=kid)
        assert r.status_code == 403 and "Time's up" in r.json()["detail"]
    # the parent can give more time
    client.patch(f"/kids/children/{child['id']}", json={"daily_limit_min": 60}, headers=h)
    assert client.get("/kids/me", headers=kid).json()["minutes_left"] == 50


def test_limit_has_sane_bounds(client):
    h = signup(client, "mama15")
    child = add_child(client, h)
    for bad in (0, 5, 500):
        assert client.patch(f"/kids/children/{child['id']}", json={"daily_limit_min": bad}, headers=h).status_code == 422


def test_deleting_a_child_erases_them_and_their_session(client):
    h, (c1, k1), (c2, k2) = make_two_kids(client, "mama16")
    with SessionLocal() as db:
        db.add(KidGameRecord(id="g_a", white_child_id=c1["id"], black_child_id=c2["id"], moves=["e2e4"],
                             result="1-0", reason="resignation"))
        db.add(KidGameRecord(id="g_b", white_child_id=c1["id"], bot_level=1, moves=["e2e4"],
                             result="1-0", reason="resignation"))
        db.commit()
    assert client.delete(f"/kids/children/{c1['id']}", headers=h).json() == {"deleted": True}
    assert [c["id"] for c in client.get("/kids/children", headers=h).json()] == [c2["id"]]
    assert client.get("/kids/me", headers=k1).status_code == 401  # their session stops working at once
    with SessionLocal() as db:
        left = {r.id: (r.white_child_id, r.black_child_id)
                for r in db.query(KidGameRecord).filter(KidGameRecord.id.in_(["g_a", "g_b"])).all()}
    assert left == {"g_a": (None, c2["id"])}  # shared game kept for the other child, bot game gone


# ---- computer opponents for kids ----------------------------------------------------------

@needs_engine
def test_kid_vs_friendly_bot_is_unrated_and_recorded(client):
    h = parent_with_pin(client, "mama17")
    child = add_child(client, h)
    kid = kid_session(client, h, child)
    g = client.post("/kids/games/ai", json={"bot": 1, "color": "white"}, headers=kid).json()
    with client.websocket_connect(f"/ws/games/{g['game_id']}") as ws:
        snap = hello(ws, g["token"])
        assert snap["players"]["black"]["name"] == "Zuri the Gentle"
        assert snap["kids"] is True and snap["rated"] is False and snap["vs_bot"] is True
        ws.send_json({"type": "move", "seq": 1, "move": "e2e4"})
        assert drain_until(ws, "move_made")["seq"] == 1
        assert drain_until(ws, "move_made")["seq"] == 2  # the bot answered
        ws.send_json({"type": "resign"})
        assert drain_until(ws, "game_over")["rating_change"] is None
    games_list = client.get("/kids/me/games", headers=kid).json()
    assert games_list[0]["opponent"] == "Zuri the Gentle" and games_list[0]["rated"] is False
    assert client.get("/kids/me", headers=kid).json()["rating"] == 1500
