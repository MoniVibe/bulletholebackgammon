# Bullethole Chess Mission

This project is at MVP stage and still needs a lot of wiring.

## Current Truth

- The current AI is intentionally dumb (random / basic tactical preference).
- This is good for local gameplay testing, but not for long-term challenge.
- There is probably more stuff we need to add and wire before release.

## Core Mission

Build a fast, fun Bullethole Chess experience that feels good to play in short sessions, then grow it into a social competitive product.

## Next Feature Tracks

### 1. Gameplay + Rules

- Finish Bullethole-specific rule behavior and edge cases.
- Add queued actions design/prototype (cooldown-ready move queueing).
- Improve move clarity (last move, legal targets, check pressure cues).

### 2. AI + Solo

- Keep dumb AI for MVP iteration speed.
- Add stronger AI tiers later (easy/normal/hard) after networking baseline.
- Add AI testing harnesses for cooldown-variant behavior.

### 3. Server Wiring

- Connect Flutter client to server-authoritative game loop.
- Sync versioned game state and cooldown timers from server time.
- Add reconnect/resync, duplicate move protection, and conflict handling.

### 4. Social Layer

- In-game chat (quick presets first, free text second).
- Emoji reactions in match.
- Lightweight post-game interactions.

### 5. Audio + Feel

- Sounds: move, capture, check, win/loss, ready/cooldown pulse.
- UI polish for better game feel: motion, feedback, readability, pacing.
- Maintain "feel good commits" that continuously improve polish.

### 6. Progression + Economy

- ELO / ranking and basic season ladder.
- Microcash-style cosmetic economy:
- Emoji packs
- Piece skins
- Board themes/skins
- Keep gameplay fair: cosmetics only, no power advantages.

### 7. Product Stability

- Add telemetry and crash/error tracking.
- Add analytics around session length, rematches, and drop-off points.
- Add smoke/regression tests for key gameplay flows.

## Build Order (Suggested)

1. Lock Bullethole rules + queued actions decision.
2. Wire server protocol + resync model.
3. Add chat + sounds + UI polish.
4. Ship ranking baseline.
5. Add cosmetics economy and content drops.
