"""Download the official Stockfish release into backend/engines/ and verify its SHA-256.

Usage: python scripts/get_stockfish.py
Stockfish is GPL-3.0: keep it on the server, never bundle it into the mobile apps.
"""
import hashlib
import io
import urllib.request
import zipfile
from pathlib import Path

VERSION = "sf_19"
URL = f"https://github.com/official-stockfish/Stockfish/releases/download/{VERSION}/stockfish-windows-x86-64-universal.zip"
SHA256 = "3c8bf1f9ea66a09350a40df4f632288285ac206d99f33ab5842c408fc30b48a7"
DEST = Path(__file__).resolve().parent.parent / "engines"

data = urllib.request.urlopen(URL).read()
digest = hashlib.sha256(data).hexdigest()
if digest != SHA256:
    raise SystemExit(f"Hash mismatch, refusing to install: {digest}")

DEST.mkdir(exist_ok=True)
with zipfile.ZipFile(io.BytesIO(data)) as z:
    (DEST / "stockfish.exe").write_bytes(z.read("stockfish/stockfish-windows-x86-64-universal.exe"))
    (DEST / "STOCKFISH-LICENSE-GPL3.txt").write_bytes(z.read("stockfish/Copying.txt"))
print("Installed", DEST / "stockfish.exe")
