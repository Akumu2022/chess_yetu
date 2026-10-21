"""Tiny forced-mate solver, enough for puzzles of mate in 1 and mate in 2."""
import chess


def mates_now(board: chess.Board) -> list[chess.Move]:
    """Moves that checkmate immediately."""
    out = []
    for mv in board.legal_moves:
        board.push(mv)
        if board.is_checkmate():
            out.append(mv)
        board.pop()
    return out


def forcing_moves(board: chess.Board, n: int) -> list[chess.Move]:
    """Moves after which the side to move mates in at most `n` of its own moves, whatever the reply."""
    if n == 1:
        return mates_now(board)
    good = []
    for mv in list(board.legal_moves):
        board.push(mv)
        ok = not board.is_game_over() and all(_reply_loses(board, r, n - 1) for r in list(board.legal_moves))
        board.pop()
        if ok:
            good.append(mv)
    return good


def _reply_loses(board: chess.Board, reply: chess.Move, n: int) -> bool:
    board.push(reply)
    try:
        return bool(forcing_moves(board, n))
    finally:
        board.pop()


def best_reply(board: chess.Board, n: int) -> chess.Move | None:
    """After the solver's move (board has the defender to move), the defender's most stubborn reply."""
    replies = list(board.legal_moves)
    if not replies:
        return None
    # Prefer a reply that needs the full n-1 follow-up, otherwise the first legal one.
    for r in replies:
        board.push(r)
        quick = bool(mates_now(board))
        board.pop()
        if not quick:
            return r
    return replies[0]
