"""Username + password accounts with signed bearer tokens."""
import hashlib
import hmac
import os
import re
import secrets
import time
from pathlib import Path

import jwt
from fastapi import Header, HTTPException

from .db import Child, SessionLocal, User

SECRET_FILE = Path(__file__).resolve().parent.parent / ".jwt_secret"


def load_or_create_secret(path: Path = SECRET_FILE) -> str:
    """A random key kept on disk, so restarting the server doesn't sign everyone out."""
    if path.exists():
        value = path.read_text().strip()
        if len(value) >= 32:
            return value
    value = secrets.token_hex(32)
    path.write_text(value)
    return value


# In production set JWT_SECRET instead (e.g. from your secrets manager).
SECRET = os.environ.get("JWT_SECRET") or load_or_create_secret()
TOKEN_TTL_S = 30 * 24 * 3600  # signed out automatically after 30 days
KID_TOKEN_TTL_S = 12 * 3600  # a kids session ends on its own
USERNAME_RE = re.compile(r"^[A-Za-z0-9_]{3,24}$")


def hash_password(password: str) -> str:
    salt = secrets.token_bytes(16)
    h = hashlib.scrypt(password.encode(), salt=salt, n=2**14, r=8, p=1)
    return f"{salt.hex()}${h.hex()}"


def verify_password(password: str, stored: str) -> bool:
    salt_hex, h_hex = stored.split("$")
    h = hashlib.scrypt(password.encode(), salt=bytes.fromhex(salt_hex), n=2**14, r=8, p=1)
    return hmac.compare_digest(h.hex(), h_hex)


def make_token(user: User) -> str:
    return jwt.encode({"sub": str(user.id), "typ": "adult", "exp": int(time.time()) + TOKEN_TTL_S},
                      SECRET, "HS256")


def make_kid_token(child: Child) -> str:
    return jwt.encode({"sub": str(child.id), "typ": "kid", "exp": int(time.time()) + KID_TOKEN_TTL_S},
                      SECRET, "HS256")


def _decode(token: str | None) -> dict | None:
    if not token:
        return None
    try:
        return jwt.decode(token, SECRET, algorithms=["HS256"])
    except jwt.PyJWTError:
        return None


def _bearer(authorization: str | None) -> str | None:
    if authorization and authorization.lower().startswith("bearer "):
        return authorization[7:]
    return None


def user_from_token(token: str | None) -> User | None:
    payload = _decode(token)
    if not payload or payload.get("typ", "adult") != "adult":
        return None
    try:
        uid = int(payload["sub"])
    except (KeyError, ValueError):
        return None
    with SessionLocal() as db:
        return db.get(User, uid)


def child_from_token(token: str | None) -> Child | None:
    payload = _decode(token)
    if not payload or payload.get("typ") != "kid":
        return None
    try:
        cid = int(payload["sub"])
    except (KeyError, ValueError):
        return None
    with SessionLocal() as db:
        return db.get(Child, cid)


def _refuse_kid_token(authorization: str | None) -> None:
    """A kids session must never reach adult features, whatever the client tries."""
    payload = _decode(_bearer(authorization))
    if payload and payload.get("typ") == "kid":
        raise HTTPException(403, "Kids accounts can only use the kids section")


def optional_user(authorization: str | None = Header(None)) -> User | None:
    _refuse_kid_token(authorization)
    return user_from_token(_bearer(authorization))


def require_user(authorization: str | None = Header(None)) -> User:
    user = optional_user(authorization)
    if not user:
        raise HTTPException(401, "Sign in required")
    return user


def require_child(authorization: str | None = Header(None)) -> Child:
    child = child_from_token(_bearer(authorization))
    if not child:
        raise HTTPException(401, "Kids session required")
    return child
