# bulletholebackgammon

Bullethole Backgammon Flutter app (sheshbesh-only repo).

Primary modes:
- `Local vs Bot`
- `Online Prototype` (transport/session shell)

## Shared package

Game-agnostic code is consumed from:
- `../bullethole-shared`

Shared scope:
- transport helpers
- shared UI primitives
- common skin model types

Backgammon rules, board layout, AI, and game state live in this repo.

## App

```bash
flutter pub get
flutter run
```

## Visual asset prep

When replacing board/coin/dice/time-bar images:

```bash
python tool/prepare_visual_assets.py
```

Generated outputs are written to `assets/generated/` and are the files used by UI.

## Windows quick launch

- Double-click `launch-dev.cmd` from repo root.
- It starts Flutter on Windows using `DEFAULT_BACKEND_URL=http://localhost:8080`.
- If no local backend folder exists, it launches app-only and prints a warning.

Optional CLI usage:

```powershell
.\launch-dev.ps1
.\launch-dev.ps1 -Device chrome
.\launch-dev.ps1 -BackendUrl https://your-backend.example.com -SkipBackend
.\launch-dev.ps1 -DryRun
```

## Mobile installer scripts

Android split APK:

```powershell
.\build-apk-split.ps1
```

iOS (macOS required):

```bash
./build-ios.sh --no-codesign
```

## Notes

- This repo does not include chess gameplay logic.
- Multiplayer backend implementation is external and can be hosted separately.
