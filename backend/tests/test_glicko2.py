from app.glicko2 import Rating, update


def test_glickman_worked_example():
    # From the Glicko-2 paper: 1500/200/0.06 vs 1400/30 (win), 1550/100 (loss), 1700/300 (loss)
    p = Rating(1500, 200, 0.06)
    out = update(p, [(Rating(1400, 30), 1), (Rating(1550, 100), 0), (Rating(1700, 300), 0)])
    assert abs(out.rating - 1464.06) < 0.05
    assert abs(out.rd - 151.52) < 0.05
    assert abs(out.vol - 0.05999) < 0.0001


def test_winner_gains_loser_drops_and_rd_shrinks():
    a, b = Rating(), Rating()
    na, nb = update(a, [(b, 1)]), update(b, [(a, 0)])
    assert na.rating > 1500 > nb.rating
    assert na.rd < 350 and nb.rd < 350
