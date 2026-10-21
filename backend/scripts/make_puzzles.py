"""Generate original mate-in-1 / mate-in-2 puzzles from randomised games (no third-party data).

    python scripts/make_puzzles.py [seconds]
Writes app/data/puzzles.json. Positions are checked with app/mates.py, so every puzzle is a verified forced mate.
"""
import json
import random
import sys
import time
from pathlib import Path

import chess

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from app.mates import forcing_moves, mates_now  # noqa: E402

OUT = Path(__file__).resolve().parent.parent / "app" / "data" / "puzzles.json"


def weighted_move(board):
    moves = list(board.legal_moves)
    w = []
    for m in moves:
        x = 1.0
        if board.is_capture(m):
            x += 3
        if board.gives_check(m):
            x += 2
        w.append(x)
    return random.choices(moves, w)[0]


def material(board):
    v = {1: 1, 2: 3, 3: 3, 4: 5, 5: 9}
    return sum(v.get(p.piece_type, 0) for p in board.piece_map().values())


def main(budget_s: float):
    random.seed()
    t0 = time.time()
    found = {1: {}, 2: {}}
    while time.time() - t0 < budget_s:
        b = chess.Board()
        for ply in range(random.randint(16, 60)):
            if b.is_game_over():
                break
            b.push(weighted_move(b))
            if ply < 14 or b.is_game_over() or b.is_check():
                continue
            if material(b) < 20:  # keep it a middlegame-looking position
                continue
            fen = b.fen()
            if fen in found[1] or fen in found[2]:
                continue
            m1 = mates_now(b)
            if m1:
                if len(m1) <= 2 and len(found[1]) < 150:
                    found[1][fen] = {"fen": fen, "depth": 1, "theme": "Mate in 1"}
                continue
            if len(found[2]) < 60 and random.random() < 0.15:
                sol = forcing_moves(b, 2)
                if len(sol) == 1:
                    found[2][fen] = {"fen": fen, "depth": 2, "theme": "Mate in 2"}
        print(f"\r{len(found[1])} mate-in-1, {len(found[2])} mate-in-2  ({int(time.time()-t0)}s)", end="", flush=True)
        if len(found[1]) >= 150 and len(found[2]) >= 60:
            break
    items = list(found[1].values()) + list(found[2].values())
    for i, p in enumerate(items, 1):
        p["id"] = i
    OUT.parent.mkdir(exist_ok=True)
    OUT.write_text(json.dumps(items, indent=0))
    print(f"\nwrote {len(items)} puzzles to {OUT}")


if __name__ == "__main__":
    main(float(sys.argv[1]) if len(sys.argv) > 1 else 120)
