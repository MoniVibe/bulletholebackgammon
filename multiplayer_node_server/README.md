# Node Matchmaking + Game Backend

This service provides:
- `POST /api/matches/join` -> auto-join open match or create one
- `POST /api/matches/create` -> alias of join (kept for compatibility)
- `GET /healthz` -> health
- `GET /debug/logs` -> structured in-memory server event log
- `WS /ws?matchId=...&playerId=...` -> real-time game channel

`GET /debug/logs` query params:
- `limit` (default `100`, max `1000`)
- `matchId` (optional filter)
- `event` (optional filter)
- `level` (optional filter)

`POST /api/matches/join` and `POST /api/matches/create` accept:
- `name` (required)
- `cooldownSeconds` (optional, only used when creating a new waiting match)
- `pieceSkinId` (optional, defaults to `chess_classic`)

It runs matchmaking and authoritative move validation in one Node.js process.

## Run locally

```bash
npm install
npm start
```

Defaults:
- bind `0.0.0.0`
- port `8080`
- match TTL disabled (`0`)

Env vars:
- `PORT`
- `BIND`
- `MATCH_TTL_MS` (`>0` enables expiry cleanup)
- `DEFAULT_COOLDOWN_SECONDS` (default `3`)
- `MAX_SERVER_LOGS` (default `500`)

## Docker

```bash
docker build -t bullethole-backend .
docker run --rm -p 8080:8080 bullethole-backend
```
