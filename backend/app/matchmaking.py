"""In-memory quick-match queue. Clients poll; entries expire if they stop polling."""
import random
import time
from dataclasses import dataclass, field

STALE_S = 6  # clients poll every 1.5s; a longer silence means the tab is gone (no ghost opponents)
BASE_WINDOW = 100  # rating points
WIDEN_PER_S = 25  # window grows while waiting


@dataclass
class Entry:
    user_id: int
    name: str
    rating: float
    minutes: int
    increment: int
    since: float = field(default_factory=time.monotonic)
    last_seen: float = field(default_factory=time.monotonic)


queue: dict[int, Entry] = {}  # user_id -> waiting entry
matched: dict[int, dict] = {}  # user_id -> seat dict, consumed on next poll


def _window(e: Entry, now: float) -> float:
    return BASE_WINDOW + WIDEN_PER_S * (now - e.since)


def _compatible(a: Entry, b: Entry, now: float) -> bool:
    return (
        a.user_id != b.user_id
        and a.minutes == b.minutes
        and a.increment == b.increment
        and abs(a.rating - b.rating) <= max(_window(a, now), _window(b, now))
    )


def _purge(now: float) -> None:
    for uid in [u for u, e in queue.items() if now - e.last_seen > STALE_S]:
        del queue[uid]


# Kids play only kids: a second, completely separate pool.
kid_queue: dict[int, Entry] = {}
kid_matched: dict[int, dict] = {}


def find_opponent(me: Entry, pool: dict[int, Entry] | None = None) -> Entry | None:
    pool = queue if pool is None else pool
    now = time.monotonic()
    for uid in [u for u, e in pool.items() if now - e.last_seen > STALE_S]:
        del pool[uid]
    best = None
    for other in pool.values():
        if _compatible(me, other, now):
            if best is None or abs(other.rating - me.rating) < abs(best.rating - me.rating):
                best = other
    return best


def randomize_colors(a: Entry, b: Entry) -> tuple[Entry, Entry]:
    """Returns (white, black)."""
    return (a, b) if random.random() < 0.5 else (b, a)


def reset() -> None:
    queue.clear()
    matched.clear()
    kid_queue.clear()
    kid_matched.clear()
