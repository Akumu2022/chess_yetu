# Chess Yetu

Competitive and kids' chess for Kenya. Build order: backend, web, then Flutter last.

## Run
    cd backend && .venv\Scripts\python -m uvicorn app.main:app --host 0.0.0.0 --port 8765
    cd web && npm run dev -- --host        # http://localhost:5273

Port 8765 (not 8000) because Docker/WSL may already hold 8000.

## Test
    cd backend && .venv\Scripts\python -m pytest -q
    cd web && npm run check

## Config
- `DATABASE_URL` (default `sqlite:///chess_yetu.db`; use a Postgres URL in production)
- `JWT_SECRET` (set a long random value in production, otherwise tokens reset on restart)
    cd web && npm run test:e2e           # real Chrome, two players; starts its own servers on 5174/8766

## Computer opponent (Stockfish)
Server-side only (GPL-3.0). Install once: `cd backend && .venv\Scripts\python scripts/get_stockfish.py`
(or set `STOCKFISH_PATH`). Without it, `/games/ai` returns 503 and the AI tests are skipped.
Levels 1-5: Beginner (random slips), Easy 1320, Medium 1700, Hard 2100, Master (full strength).

## Docker (Postgres + API with Stockfish + web)

    docker compose up -d --build      # then open http://localhost:8081
    psql postgresql://chess:chess_dev_password@localhost:5433/chess_yetu

Host ports are 8081 (web), 8780 (API) and 5433 (Postgres), chosen to avoid clashes with other local stacks.
Copy `.env.example` to `.env` and set `POSTGRES_PASSWORD` and `JWT_SECRET` for anything beyond local use.
The API keeps live games and the matchmaking queue in memory, so run exactly one API container.

Run the backend tests against Postgres: create a throwaway database, then
`TEST_DATABASE_URL=postgresql+psycopg://chess:<password>@localhost:5433/chess_test python -m pytest`.

Puzzles: `python backend/scripts/make_puzzles.py [seconds]` regenerates `backend/app/data/puzzles.json`.
