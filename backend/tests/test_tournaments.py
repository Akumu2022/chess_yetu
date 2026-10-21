import pytest
from fastapi.testclient import TestClient

from app import kids, matchmaking, tournaments
from app.main import _finalize, app, games
from app.tournaments import Cand, pick_pairs

from tests.test_kids import parent_with_pin, signup


@pytest.fixture
def client():
    games.clear()
    matchmaking.reset()
    tournaments.reset()
    with TestClient(app) as c:
        yield c


def test_pairing_prefers_neighbours_and_avoids_instant_rematches():
    cands = [Cand(1, 6, 0), Cand(2, 5, 0), Cand(3, 1, 0), Cand(4, 0, 0)]
    pairs = pick_pairs(cands, {})
    assert [(a.user_id, b.user_id) for a, b in pairs] == [(1, 2), (3, 4)]
    # 1 just played 2, so 1 meets the next one down; 2 gets someone else
    pairs = pick_pairs(cands, {1: 2, 2: 1})
    assert (1, 3) in [(a.user_id, b.user_id) for a, b in pairs]
    # but two players who have waited long enough may rematch rather than sit out
    pairs = pick_pairs([Cand(1, 3, 40), Cand(2, 3, 40)], {1: 2, 2: 1})
    assert len(pairs) == 1
    assert pick_pairs([Cand(1, 3, 2), Cand(2, 3, 2)], {1: 2, 2: 1}) == []
    assert pick_pairs([Cand(1, 0, 0)], {}) == []  # an odd player waits


def make(client, h, **kw):
    body = {"name": "Friday Blitz", "minutes": 3, "increment": 0, "starts_in_min": 0, "duration_min": 10, **kw}
    return client.post("/tournaments", json=body, headers=h)


def test_creating_and_validation(client):
    h = signup(client, "tr_org")
    r = make(client, h)
    assert r.status_code == 200 and r.json()["status"] == "running" and r.json()["players"] == 0
    assert make(client, h, name="x").status_code == 422
    assert make(client, h, minutes=99).status_code == 422
    assert make(client, h, duration_min=5).status_code == 422
    assert client.post("/tournaments", json={"name": "Nope nope", "minutes": 3}).status_code == 401
    assert make(client, h, starts_in_min=60).json()["status"] == "upcoming"
    assert make(client, h).status_code == 200
    assert make(client, h).status_code == 429  # three open at once is the limit


def test_kids_cannot_touch_tournaments(client):
    h = parent_with_pin(client, "tr_mama")
    c = client.post("/kids/children", json={"birth_year": kids.datetime.now(kids.EAT).year - 8, "consent": True}, headers=h).json()
    kid = {"Authorization": "Bearer " + client.post(f"/kids/children/{c['id']}/session", headers=h).json()["token"]}
    assert client.get("/tournaments", headers=kid).status_code == 403
    assert client.post("/tournaments/1/join", headers=kid).status_code == 403


def test_full_arena_flow_pairs_scores_and_ranks(client):
    org, a, b, c = (signup(client, f"tr_{n}") for n in ("org2", "ann", "ben", "cy"))
    tid = make(client, org).json()["id"]
    assert client.get(f"/tournaments/{tid}/me", headers=a).json()["status"] == "not_joined"
    for h in (a, b, c):
        assert client.post(f"/tournaments/{tid}/join", headers=h).json()["joined"]
    assert next(t for t in client.get("/tournaments", headers=a).json() if t["id"] == tid)["joined"] is True

    # everyone is present; three players -> one game, one waits
    for h in (a, b, c):
        client.get(f"/tournaments/{tid}/me", headers=h)
    assert tournaments.pair_once(games) == 1
    seats = {n: client.get(f"/tournaments/{tid}/me", headers=h).json() for n, h in (("a", a), ("b", b), ("c", c))}
    matched = {n: s for n, s in seats.items() if s["status"] == "matched"}
    waiting = [n for n, s in seats.items() if s["status"] == "waiting"]
    assert len(matched) == 2 and len(waiting) == 1
    # the seat is handed over once only
    n0 = next(iter(matched))
    assert client.get(f"/tournaments/{tid}/me", headers={"a": a, "b": b, "c": c}[n0]).json()["status"] == "waiting"

    game = games[next(iter(matched.values()))["seat"]["game_id"]]
    assert game.tournament_id == tid and game.rated and game.status == "active"
    # nobody is paired again while a game is running
    for h in (a, b, c):
        client.get(f"/tournaments/{tid}/me", headers=h)
    assert tournaments.pair_once(games) == 0

    game.resign("black")
    _finalize(game)
    st = client.get(f"/tournaments/{tid}").json()["standings"]
    by = {r["username"]: r for r in st}
    white_name = game.players["white"]["name"]
    black_name = game.players["black"]["name"]
    assert by[white_name]["points"] == 2 and by[white_name]["wins"] == 1
    assert by[black_name]["points"] == 0 and by[black_name]["losses"] == 1
    assert st[0]["username"] == white_name and st[0]["rank"] == 1
    _finalize(game)  # finishing twice must not score twice
    assert client.get(f"/tournaments/{tid}").json()["standings"][0]["points"] == 2


def test_players_who_left_the_page_are_not_paired_and_can_withdraw(client):
    org, a, b = (signup(client, f"tr_{n}") for n in ("org3", "dee", "eli"))
    tid = make(client, org).json()["id"]
    client.post(f"/tournaments/{tid}/join", headers=a)
    client.post(f"/tournaments/{tid}/join", headers=b)
    tournaments.present[(tid, 0)] = 0  # unrelated key must not matter
    for key in list(tournaments.present):
        tournaments.present[key] -= 60  # both pages went quiet a minute ago
    assert tournaments.pair_once(games) == 0
    client.get(f"/tournaments/{tid}/me", headers=a)
    client.get(f"/tournaments/{tid}/me", headers=b)
    assert tournaments.pair_once(games) == 1
    assert client.delete(f"/tournaments/{tid}/join", headers=a).json()["joined"] is False
    assert client.get(f"/tournaments/{tid}/me", headers=a).json()["status"] == "not_joined"


def test_ended_tournament_cannot_be_joined_and_declares_a_winner(client):
    org, a = signup(client, "tr_org4"), signup(client, "tr_fay")
    tid = make(client, org).json()["id"]
    client.post(f"/tournaments/{tid}/join", headers=a)
    from app.db import SessionLocal, Tournament
    from datetime import timedelta
    with SessionLocal() as db:
        t = db.get(Tournament, tid)
        t.starts_at = tournaments.now() - timedelta(minutes=t.duration_min + 1)
        db.commit()
    assert client.post(f"/tournaments/{tid}/join", headers=a).status_code == 409
    d = client.get(f"/tournaments/{tid}").json()
    assert d["status"] == "finished" and d["winner"] is None  # nobody played
    assert client.get("/tournaments/9999").status_code == 404
