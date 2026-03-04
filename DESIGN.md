# Bullethole Chess – Design Document

Real-time asynchronous chess variant with cooldown-based turn mechanics. Server-authoritative, WebSocket-based, versioned state.

---

## 1) Treat the server as the referee (always)

The variant is fundamentally **real-time / asynchronous**, so use a **server-authoritative** model:

- Clients send **inputs** (a move)
- Server validates, applies, and broadcasts the updated state

This is the standard anti-cheat + consistency pattern for multiplayer games. ([Heroic Labs](https://heroiclabs.com/docs/nakama/concepts/multiplayer/authoritative/))

---

## 2) Use WebSockets (Socket.IO is fine)

Low-latency, bidirectional updates for “move accepted”, “state changed”, “cooldown tick”, “opponent reconnected”, etc. Socket.IO fits event-based, realtime client–server communication. ([Socket.IO](https://socket.io/docs/v4/))

**Flutter options:**

- **Socket.IO client**: `socket_io_client` package ([Dart packages](https://pub.dev/packages/socket_io_client))
- **Raw WebSocket**: Flutter’s `web_socket_channel` (simpler protocol, less magic). ([docs.flutter.dev](https://docs.flutter.dev/cookbook/networking/web-sockets))

If using Node + “game rooms”, Socket.IO is a comfortable fit.

---

## 3) Define the game state like a tiny database record

Minimum server-side state per match:

| Field           | Type                              | Description                            |
|----------------|-----------------------------------|----------------------------------------|
| `gameId`       | string                            | Match identifier                       |
| `version`      | integer (monotonic)               | Increments each accepted move          |
| `fen`          | string                            | Board position                         |
| `lastMover`    | `"w"` or `"b"`                    | Last color to move                     |
| `cooldownEndsAt` | `{ w: epochMs, b: epochMs }`    | Cooldown end times (server epoch ms)   |
| `moveHistory`  | array                             | Moves in UCI-style (from, to, promotion) |
| `enPassantQueue` | `[{ square, createdAt }]` (FIFO) | When enabled: queued en passant targets |
| `enPassantEnabled` | boolean                       | Toggle: en passant rule on/off per game |

### Why `version` matters

Both players can be off cooldown and send moves close together. You need a way to reject moves based on stale state.

---

## 4) Validate moves on the server with a chess rules library

On Node, **chess.js** is a solid choice for move generation/validation and check/checkmate detection. ([GitHub](https://github.com/jhlywa/chess.js))

### The key twist: variant breaks strict alternation

Do **not** rely on “side to move” as the sole gate. Use this flow instead:

**On move request from color C:**

1. **Auth**: Is this socket allowed to play as C in this `gameId`?
2. **Cooldown**: Is `now >= cooldownEndsAt[C]`? (Use server time.)
3. **Version**: Request includes `clientVersion`. If it’s not equal to server `version`, reject with 409 Conflict and send latest snapshot.
4. **Move legality**:
   - Take current FEN
   - Force the “active color” field in FEN to **C**
   - Apply move `{from, to, promotion}`
   - Ensure mover’s king is not left in check
5. **On acceptance**:
   - Update `fen`, `version++`, `lastMover = C`
   - **Cooldown update**:
     - `cooldownEndsAt[C] = now + N*1000` (default `N = 7` seconds)
     - `cooldownEndsAt[other] = now` (effectively 0)

Then broadcast the new state to both clients.

### Socket.IO acknowledgements

Use Socket.IO “ack” callbacks for `move` so the client gets an immediate accept/reject and reason. ([Socket.IO](https://socket.io/docs/v4/emitting-events/))

---

## 5) Rule edge cases (decide now, not later)

### A) Near-simultaneous moves

**Recommendation:**

- Server processes moves **one at a time** in arrival order.
- A move is accepted only if it matches the current `version`.
- If stale: reject and push a resync.

Simple, deterministic, debuggable.

### B) En passant – toggleable queued order

En passant is defined around “the opponent’s next move”; in this variant the opponent can skip, so opportunities can pile up.

**Rule:**

- **Toggleable**: En passant can be enabled/disabled per game or in settings.
- **Queued order**: Maintain a FIFO queue of en passant target squares (one per opponent double-pawn push). When a pawn has a legal en passant capture, it engages against the **first available** target in the queue (oldest opportunity).

**Implementation:** Track `enPassantQueue: [{ square, createdAt }]`. On opponent double-push, append. On en passant capture, consume the first matching valid entry. Clear consumed and stale entries as moves resolve.

---

## 6) Flutter client: UI first, logic second

Build the board UI first, then wire it to server state.

**Board widgets:**

- `flutter_chess_board` (board widget + FEN/PGN/SAN support) ([Dart packages](https://pub.dev/documentation/flutter_chess_board/latest/))
- Lichess’s `flutter-chessground` ([GitHub](https://github.com/lichess-org/flutter-chessground))

**Client-side chess logic (optional, for legal move highlighting):**

- `chess` (Dart port of chess.js; BSD-2-Clause/MIT) ([Dart packages](https://pub.dev/packages/chess))
- `dartchess` (GPL-3.0; licensing considerations) ([Dart packages](https://pub.dev/packages/dartchess))

Client-side validation is for UX only; **the server is the source of truth**.

---

## 7) Minimal realtime protocol (Socket.IO or raw WebSocket)

**Client → Server**

| Event         | Payload                                                                 |
|---------------|-------------------------------------------------------------------------|
| `queue.join` / `game.create` / `game.join` | (matchmaking / join)                                           |
| `game.move`   | `{ gameId, clientVersion, move: {from, to, promotion?}, clientMoveId }` |

**Server → Client**

| Event            | Payload                                                                 |
|------------------|-------------------------------------------------------------------------|
| `game.state`     | `{ gameId, version, fen, cooldownEndsAt, lastMove, status }`            |
| `game.moveResult` (via ack) | `{ ok, reason?, newState? }`                              |
| `game.error`     | (hard failures)                                                         |

**Always include:**

- `serverNow` in `game.state` so clients can compute a stable countdown without trusting their own clock.

---

## 8) Scaling on Azure

If you run multiple Node instances:

- Socket.IO typically needs **sticky sessions**, even with the Redis adapter. ([Socket.IO Redis](https://socket.io/docs/v4/redis-adapter/))

**Azure:** Microsoft’s **Azure Web PubSub for Socket.IO** offloads realtime scaling (up to 100k concurrent connections). ([Microsoft Learn](https://learn.microsoft.com/en-us/azure/azure-web-pubsub/socketio-service-internal))

Keep the server “stateless-ish” where possible; store match state in Redis or a DB so it survives restarts.

---

## 9) Build order (fastest path to playable)

1. **Node**: Matchmaking + single in-memory match + validate/apply move + broadcast state
2. **Flutter**: Board UI that renders server FEN + sends moves
3. Add cooldown UI (using `cooldownEndsAt` and `serverNow`)
4. Add reconnection/resync (client requests `game.state` on reconnect)
5. Add persistence + matchmaking polish

---

## Open design decisions

- **Cooldown N**: Default **7 seconds**. Fixed? Upgrades? Per-game? (TBD)
- **Win condition**: Standard checkmate vs something variant-specific?
