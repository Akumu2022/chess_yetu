import asyncio

from starlette.websockets import WebSocketDisconnected

from app.game import Game
from app.main import game_socket, games, sockets


class DeadAfterHello:
    """A client whose connection vanished right after saying hello: the next read raises
    WebSocketDisconnected, exactly what Starlette does after a failed send to a dropped phone."""

    def __init__(self, token):
        self.token = token
        self.sent = []
        self.said_hello = False

    async def accept(self):
        pass

    async def receive_json(self):
        if not self.said_hello:
            self.said_hello = True
            return {"type": "hello", "v": 1, "token": self.token}
        raise WebSocketDisconnected('WebSocket is not connected. Need to call "accept" first.')

    async def send_json(self, msg):
        self.sent.append(msg)

    async def close(self):
        pass


def test_a_dropped_connection_is_cleaned_up_quietly():
    games.clear()
    sockets.clear()
    g = Game(id="drop1", initial_ms=60_000, increment_ms=0)
    _, token = g.add_player()
    g.add_player()
    games[g.id] = g

    ws = DeadAfterHello(token)
    asyncio.run(game_socket(ws, g.id))  # must finish without raising

    assert ws.sent[0]["type"] == "resync"
    assert "white" not in sockets.get("drop1", {})  # the dead socket was removed
