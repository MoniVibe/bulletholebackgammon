# Multiplayer Relay Server

Authoritative WebSocket relay for the Bullethole Chess online prototype.

## Run

```bash
dart pub get
dart run bin/server.dart
```

Env vars:
- `HOST` (default `0.0.0.0`)
- `PORT` (default `8080`)

## Protocol (JSON)

Client -> server:
- `join`: `{ "type": "join", "roomId": "abc", "name": "Dekel" }`
- `move`: `{ "type": "move", "from": "e2", "to": "e4", "promotion": "q" }`
- `new_game`: `{ "type": "new_game" }`

Server -> client:
- `welcome`
- `state`
- `error`
- `opponent_left`
