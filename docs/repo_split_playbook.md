# Repo Split Playbook

This project currently contains chess + backgammon.  
Target architecture:
- `bullethole-chess` (app repo)
- `bullethole-backgammon` (app repo)
- `bullethole-shared` (pure Flutter shared library repo)

## 1) Publish shared library first

1. Create a new repo and copy `packages/bullethole_shared` into it.
2. Keep package name as `bullethole_shared`.
3. Tag a first release (example: `v0.1.0`).

## 2) Wire chess repo to shared package

In `bullethole-chess/pubspec.yaml`, use:

```yaml
dependencies:
  bullethole_shared:
    git:
      url: git@github.com:<org>/bullethole-shared.git
      ref: v0.1.0
```

Then run:

```bash
flutter pub get
flutter test
```

## 3) Create backgammon repo from this codebase

Recommended bootstrap:
1. Copy this repo to a new directory.
2. Remove chess-only engine/UI files (`online_game_controller.dart`, `online_game_panel.dart`, chess board/piece assets and tests).
3. Keep `LocalGameController` + sheshbesh rule/board/AI files.
4. Point the new repo to `bullethole_shared` as shown above.
5. Rename app metadata (`pubspec.yaml`, app title, bundle ids).

## 4) Shared package boundaries

Only keep game-agnostic code in `bullethole_shared`:
- Generic UI widgets/components
- Generic menu/time-bar controls
- Skin metadata models
- Multiplayer transport helpers/utilities

Do not put game rules or game-specific assets in shared.
