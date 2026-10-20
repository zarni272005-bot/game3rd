# Island Arena

A small Godot 4 third-person-style multiplayer arena starter. The island and player models are generated in code, so no external art assets are required.

## Current scope

- Godot 4 scene with a procedural island, player models, keyboard controls, and on-screen touch buttons.
- WebSocket multiplayer with server-authoritative movement and a 32-player connection limit.
- FastAPI REST API for persistent match metadata.
- SQLite for local development; PostgreSQL with a persistent Docker volume for deployment.
- Backend tests for health, match creation/listing/status updates, and input validation.

This is a working starter, not a production-hardened live-service game. It has no account system, matchmaking queue, anti-cheat, telemetry, or automated database migrations. Add authentication, rate limiting, migrations, monitoring, and load testing before exposing the API or game server to the public internet.

## Run locally

1. Open this folder in Godot 4 and press **F6** or **F5**.
2. Start the API in a terminal:

   ```powershell
   py -m venv .venv
   .\.venv\Scripts\Activate.ps1
   python -m pip install -r requirements.txt
   python -m uvicorn backend.main:app --reload
   ```

   Run the API tests with `python -m pytest -q backend\tests`.

3. Press **Host** in the game, or run a dedicated headless game server:

   ```powershell
   godot --headless --path . -- --server
   ```

4. Run another game instance, enter `ws://127.0.0.1:9080`, and press **Join**.

The API defaults to `http://127.0.0.1:8000`. Set `ARENA_API_URL` on the machine running the game server to override it. The game still starts when the API is unavailable; the HUD reports that match metadata could not be saved.

For LAN play, clients should use the host computer's LAN address. Allow inbound TCP port `9080` through the host firewall. Use a TLS-enabled reverse proxy and `wss://` for internet/browser deployments.

## API

- `GET /health` — checks API and database connectivity.
- `POST /v1/matches` — creates a match record.
- `GET /v1/matches?status=open&limit=50` — lists recent matches.
- `PATCH /v1/matches/{id}` — updates match status (`open`, `in_progress`, or `closed`).
- `GET /docs` — interactive local API documentation.

The default SQLite database is created at `data/arena.db`. To run the API with persistent PostgreSQL:

```powershell
$env:POSTGRES_PASSWORD = "use-a-long-random-password"
docker compose up --build
```

The API image runs two worker processes, schema creation is serialized for PostgreSQL, and database storage is in a named Docker volume. The game server currently handles one arena with up to 32 players; multiple arenas need a matchmaking and server-routing layer. This is a scalable starting point, not a load-tested capacity guarantee. Public deployments still need secure secret management, TLS, API authentication/authorization, database migrations, backups, and capacity testing.

## Controls

- Desktop: **WASD** or arrow keys to move; **Space** to jump.
- Touch devices: on-screen direction and jump buttons.

The project uses WebSockets so clients can be exported for Godot's supported desktop and mobile targets, and for Web where the chosen Godot version/export settings support WebSocket multiplayer. For production browser play, configure HTTPS/WSS and validate the exact export target.
