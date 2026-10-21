"""Pure game logic: rules, clocks, sequence numbers. No networking here."""
import secrets
import time
from dataclasses import dataclass, field

import chess

LAG_CREDIT_CAP_MS = 500


def _now_ms() -> int:
    return int(time.monotonic() * 1000)


class GameError(Exception):
    def __init__(self, code: str, message: str = ""):
        super().__init__(message or code)
        self.code = code


@dataclass
class Game:
    id: str
    initial_ms: int
    increment_ms: int
    tokens: dict[str, str] = field(default_factory=dict)  # color -> secret token
    board: chess.Board = field(default_factory=chess.Board)
    clocks: dict[str, int] = field(default_factory=dict)
    moves: list[str] = field(default_factory=list)  # UCI, index+1 == seq
    status: str = "waiting"  # waiting | active | over
    result: str | None = None
    reason: str | None = None
    turn_started: int = 0
    draw_offer: str | None = None  # color that offered
    user_ids: dict[str, int] = field(default_factory=dict)  # color -> account id (if signed in)
    players: dict[str, dict] = field(default_factory=dict)  # color -> {"name", "rating"} for display
    finalized: bool = False  # ratings/record already saved
    kids: bool = False  # a game in the kids section: own rating pool, preset chat only
    kid_ids: dict[str, int] = field(default_factory=dict)  # color -> child id
    started_wall: float = 0.0  # time.time() when play began, for time-spent limits
    bot_color: str | None = None  # set when the opponent is the computer
    bot_level: int | None = None
    tournament_id: int | None = None  # set for arena games

    def __post_init__(self):
        self.clocks = {"white": self.initial_ms, "black": self.initial_ms}

    @property
    def seq(self) -> int:
        return len(self.moves)

    @property
    def turn(self) -> str:
        return "white" if self.board.turn == chess.WHITE else "black"

    @property
    def rated(self) -> bool:
        ids = list((self.kid_ids if self.kids else self.user_ids).values())
        return len(ids) == 2 and ids[0] != ids[1]

    def add_player(self, user_id: int | None = None, name: str = "Guest",
                   rating: float | None = None, color: str | None = None,
                   kid_id: int | None = None) -> tuple[str, str]:
        """Seat a player (the next free colour unless one is asked for); returns (color, token)."""
        if (user_id is not None and user_id in self.user_ids.values()) or (
            kid_id is not None and kid_id in self.kid_ids.values()
        ):
            raise GameError("already_seated", "You are already in this game")
        for color in ([color] if color else ["white", "black"]):
            if color not in self.tokens:
                token = secrets.token_urlsafe(16)
                self.tokens[color] = token
                if user_id is not None:
                    self.user_ids[color] = user_id
                if kid_id is not None:
                    self.kid_ids[color] = kid_id
                self.players[color] = {"name": name, "rating": None if rating is None else round(rating)}
                if len(self.tokens) == 2:
                    self._start()
                return color, token
        raise GameError("game_full", "Game already has two players")

    def seat_bot(self, color: str, level: int, name: str, rating: int | None) -> None:
        """Fill a colour with the computer. Its token is never handed out, so no socket can claim it."""
        self.tokens[color] = secrets.token_urlsafe(32)
        self.players[color] = {"name": name, "rating": rating}
        self.bot_color, self.bot_level = color, level
        if len(self.tokens) == 2:
            self._start()

    def _start(self) -> None:
        self.status = "active"
        self.turn_started = _now_ms()
        self.started_wall = time.time()

    @property
    def bot_to_move(self) -> bool:
        return self.bot_color is not None and self.status == "active" and self.turn == self.bot_color

    def color_for(self, token: str | None) -> str | None:
        for color, t in self.tokens.items():
            if token and secrets.compare_digest(t, token):
                return color
        return None

    def live_clocks(self) -> dict[str, int]:
        """Clock values right now, including time burning for the side to move."""
        c = dict(self.clocks)
        if self.status == "active":
            c[self.turn] = max(0, c[self.turn] - (_now_ms() - self.turn_started))
        return c

    def check_flag(self) -> bool:
        """End the game if the side to move has run out of time."""
        if self.status == "active" and self.live_clocks()[self.turn] <= 0:
            self.clocks[self.turn] = 0
            winner = "black" if self.turn == "white" else "white"
            self._finish(winner, "timeout")
            return True
        return False

    def play(self, color: str, seq: int, uci: str, lag_credit_ms: int = 0) -> dict:
        """Apply a move. `seq` is the sequence number the client expects this move to get."""
        if self.status != "active":
            raise GameError("not_active", "Game is not in progress")
        if color != self.turn:
            raise GameError("not_your_turn")
        if seq != self.seq + 1:
            raise GameError("bad_seq", f"expected seq {self.seq + 1}")
        if self.check_flag():
            raise GameError("timeout", "Your time ran out")
        try:
            move = chess.Move.from_uci(uci)
        except ValueError:
            raise GameError("illegal_move", uci)
        if move not in self.board.legal_moves:
            raise GameError("illegal_move", uci)

        now = _now_ms()
        credit = max(0, min(lag_credit_ms, LAG_CREDIT_CAP_MS))
        elapsed = max(0, now - self.turn_started - credit)
        self.clocks[color] = self.clocks[color] - elapsed
        if self.clocks[color] <= 0:
            self.clocks[color] = 0
            self._finish("black" if color == "white" else "white", "timeout")
            raise GameError("timeout", "Your time ran out")
        self.clocks[color] += self.increment_ms

        self.board.push(move)
        self.moves.append(uci)
        self.turn_started = now
        self.draw_offer = None

        self._check_end()
        return {"seq": self.seq, "move": uci, "clocks": self.clocks_view()}

    def resign(self, color: str) -> None:
        if self.status == "active":
            self._finish("black" if color == "white" else "white", "resignation")

    def offer_draw(self, color: str) -> bool:
        """Returns True if the draw was accepted (opponent had already offered)."""
        if self.status != "active":
            raise GameError("not_active")
        if self.draw_offer and self.draw_offer != color:
            self._finish(None, "agreement")
            return True
        self.draw_offer = color
        return False

    def clocks_view(self) -> dict[str, int]:
        return {"white": self.clocks["white"], "black": self.clocks["black"]}

    def snapshot(self) -> dict:
        """Full state, used for resync after a reconnect."""
        return {
            "game_id": self.id,
            "status": self.status,
            "fen": self.board.fen(),
            "moves": list(self.moves),
            "seq": self.seq,
            "turn": self.turn,
            "clocks": self.live_clocks(),
            "increment": self.increment_ms,
            "result": self.result,
            "reason": self.reason,
            "draw_offer": self.draw_offer,
            "players": self.players,
            "vs_bot": self.bot_color is not None,
            "kids": self.kids,
            "tournament": self.tournament_id,
            "rated": self.rated,
        }

    def _check_end(self) -> None:
        b = self.board
        if b.is_checkmate():
            self._finish("white" if b.turn == chess.BLACK else "black", "checkmate")
        elif b.is_stalemate():
            self._finish(None, "stalemate")
        elif b.is_insufficient_material():
            self._finish(None, "insufficient_material")
        elif b.can_claim_threefold_repetition() and b.is_repetition(3):
            self._finish(None, "repetition")
        elif b.is_fifty_moves():
            self._finish(None, "fifty_moves")

    def _finish(self, winner: str | None, reason: str) -> None:
        self.status = "over"
        self.reason = reason
        self.result = {"white": "1-0", "black": "0-1"}.get(winner, "1/2-1/2")
