"""Glicko-2 rating update (Glickman, 2013). One call = one rating period."""
import math
from dataclasses import dataclass

TAU = 0.5  # system constant: how fast volatility may change
SCALE = 173.7178
EPS = 1e-6


@dataclass
class Rating:
    rating: float = 1500.0
    rd: float = 350.0
    vol: float = 0.06


def _g(phi: float) -> float:
    return 1 / math.sqrt(1 + 3 * phi**2 / math.pi**2)


def _E(mu: float, mu_j: float, phi_j: float) -> float:
    return 1 / (1 + math.exp(-_g(phi_j) * (mu - mu_j)))


def update(player: Rating, results: list[tuple[Rating, float]]) -> Rating:
    """`results` is a list of (opponent, score) with score 1 / 0.5 / 0."""
    mu = (player.rating - 1500) / SCALE
    phi = player.rd / SCALE
    sigma = player.vol

    if not results:  # inactivity only widens RD
        return Rating(player.rating, min(350.0, math.sqrt(phi**2 + sigma**2) * SCALE), sigma)

    v_inv = 0.0
    delta_sum = 0.0
    for opp, score in results:
        mu_j = (opp.rating - 1500) / SCALE
        phi_j = opp.rd / SCALE
        e = _E(mu, mu_j, phi_j)
        v_inv += _g(phi_j) ** 2 * e * (1 - e)
        delta_sum += _g(phi_j) * (score - e)
    v = 1 / v_inv
    delta = v * delta_sum

    # Solve for the new volatility with the Illinois algorithm.
    a = math.log(sigma**2)

    def f(x: float) -> float:
        ex = math.exp(x)
        return ex * (delta**2 - phi**2 - v - ex) / (2 * (phi**2 + v + ex) ** 2) - (x - a) / TAU**2

    A = a
    if delta**2 > phi**2 + v:
        B = math.log(delta**2 - phi**2 - v)
    else:
        k = 1
        while f(a - k * TAU) < 0:
            k += 1
        B = a - k * TAU
    fA, fB = f(A), f(B)
    while abs(B - A) > EPS:
        C = A + (A - B) * fA / (fB - fA)
        fC = f(C)
        if fC * fB <= 0:
            A, fA = B, fB
        else:
            fA /= 2
        B, fB = C, fC
    new_sigma = math.exp(A / 2)

    phi_star = math.sqrt(phi**2 + new_sigma**2)
    new_phi = 1 / math.sqrt(1 / phi_star**2 + 1 / v)
    new_mu = mu + new_phi**2 * delta_sum
    return Rating(new_mu * SCALE + 1500, min(350.0, new_phi * SCALE), new_sigma)
