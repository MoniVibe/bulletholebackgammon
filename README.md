# bulletholebackgammon

Bullethole Backgammon Flutter app (sheshbesh-only repo).

Primary mode:
- `Local vs Bot`

## Shared package

Game-agnostic code lives in the sibling shared repo and is consumed
from this app via path dependency:
- `../bullethole-shared`
- Shared multiplayer transport lifecycle lives there (`MultiplayerTransportClient`).
- Backgammon rules/state handling stays in this repo.

Split guidance for carving chess/backgammon into separate repos is in:
- `docs/repo_split_playbook.md`

## App

```bash
flutter pub get
flutter run
```

### Visual asset prep (new art drops)

When replacing board/piece/time-bar images, preprocess them into transparent
runtime assets:

```bash
python tool/prepare_visual_assets.py
```

Generated outputs are written to `assets/generated/` and are the files used by
the app UI.

### Windows quick launch (double-click)

- Double-click `launch-dev.cmd` from the repo root.
- It opens:
  - backend (`multiplayer_node_server`, `npm start`)
  - app (`flutter run -d windows` with `DEFAULT_BACKEND_URL=http://localhost:8080`)

Optional CLI usage:

```powershell
.\launch-dev.ps1
.\launch-dev.ps1 -Device chrome
.\launch-dev.ps1 -BackendUrl https://your-backend.example.com -SkipBackend
.\launch-dev.ps1 -DryRun
```

### Android split APK build (release)

- Double-click `build-apk-split.cmd` from repo root.
- It runs `flutter build apk --release --split-per-abi` and prints SHA-256 hashes.

Optional CLI usage:

```powershell
.\build-apk-split.ps1
.\build-apk-split.ps1 -Clean
.\build-apk-split.ps1 -FlutterExe "C:\dev\flutter\bin\flutter.bat"
```

Output folder:

- `build\app\outputs\flutter-apk\`
- `app-arm64-v8a-release.apk` (most modern Android phones)
- `app-armeabi-v7a-release.apk` (older 32-bit phones)
- `app-x86_64-release.apk` (mostly emulators)

### iOS build shortcut

iOS builds require macOS + Xcode (cannot be produced on Windows directly).

- On Windows, `build-ios.cmd` prints the exact macOS command.
- On macOS, run from repo root:

```bash
./build-ios.sh --no-codesign
```

For signed IPA export:

```bash
./build-ios.sh --export-options-plist ios/ExportOptions.plist
```

Output paths:

- unsigned zip (from `--no-codesign`): `build/ios/iphoneos/Runner-no-codesign.zip`
- signed IPA (when signing succeeds): `build/ios/ipa/Runner.ipa`

### One-click installers from GitHub Actions

Use workflow `.github/workflows/mobile-installers.yml` (`Actions` -> `Mobile Installers` -> `Run workflow`).

Artifacts produced:

- `android-installers`
  - `app-release.apk` (universal installer)
  - split APKs (`arm64-v8a`, `armeabi-v7a`, `x86_64`)
  - `app-release.aab` (Google Play upload)
  - checksum file: `android-sha256.txt`
- `ios-unsigned-installer`
  - `Runner-no-codesign.zip`
  - checksum file: `ios-unsigned-sha256.txt`

Note: unsigned iOS artifacts are for packaging/verification only; installation on iOS devices requires a signed IPA generated on macOS with valid Apple signing credentials.

### Windows quick launch for AI-vs-AI bug hunt

- Double-click `run-ai-duel.cmd` from repo root.
- It picks a random seed and writes logs under `debug/`.

Optional CLI usage:

```powershell
.\run-ai-duel.ps1
.\run-ai-duel.ps1 -Games 300 -MaxPlies 260
.\run-ai-duel.ps1 -Seed 123456 -Games 80
.\run-ai-duel.ps1 -Games 150 -MaxConversionFailures 3
```

## Flutter Side-Project CI Clone

This repo now includes a dedicated Flutter-only CI lane that is separate from Azure deploy workflows:

- `.github/workflows/flutter-side-ci.yml`
  - runs on PRs/pushes for Flutter files
  - checks formatting, `flutter analyze`, `flutter test`
  - runs deterministic AI-vs-AI smoke duels
  - fails if `conversion_failure` count exceeds threshold
  - uploads `ai-duel-weird-logs-smoke` artifact (JSONL + PGN dumps)
- `.github/workflows/flutter-side-nightly-ai-duels.yml`
  - nightly stress duels for bug hunting
  - can also be run manually via `workflow_dispatch`
  - enforces a higher `conversion_failure` threshold for long runs
  - uploads `ai-duel-weird-logs-nightly` artifact (JSONL + PGN dumps)

Local duel command:

```bash
dart run tool/ai_duel.dart --games=60 --max-plies=220 --seed=20260226 --conversion-fail-cap-adv=5
```

Local duel command with weird-log file output:

```bash
dart run tool/ai_duel.dart --games=150 --max-plies=240 --seed=20260226 --conversion-fail-cap-adv=5 --max-conversion-failures=3 --log-file=debug/ai-duel-weird.jsonl
```

Local duel command with explicit PGN dump folder:

```bash
dart run tool/ai_duel.dart --games=150 --max-plies=240 --seed=20260226 --log-file=debug/ai-duel-weird.jsonl --pgn-dir=debug/ai-duel-weird-pgn
```

If `--log-file` is provided and `--pgn-dir` is omitted, PGNs are written automatically to a sibling folder based on log name (for example `debug/ai-duel-weird.jsonl` -> `debug/ai-duel-weird-pgn`).

Weird logs include capped games, repeated positions (loop-like behavior), long no-progress sequences, and `conversion_failure` events.
Each weird event also includes `legalMoveCount` and `materialSignature` for faster diagnosis.
For capped events, logs also include `materialAdvantageAtCap` (white minus black material score).
If a duel fails, the script prints the seed, game index, ply, FEN, and recent moves.
Summary output also includes termination-reason counts (checkmates, draw reasons, capped, failures) and conversion-failure totals.

## Seamless Cross-Continent Multiplayer (Prototype)

Use the Node backend in `multiplayer_node_server/` and deploy it to one public HTTPS URL.

### 1) Run backend locally

```bash
cd multiplayer_node_server
npm install
npm start
```

### 2) Play from app

In `Online Prototype` mode:
- set `Backend URL` (example: `https://your-backend.example.com`)
- host clicks `Create Invite`
- share invite code
- friend enters same `Backend URL` + code and clicks `Join Invite`

No port forwarding or custom peer-to-peer networking is needed.

## Azure Prototype Deployment (Container Apps)

1. Build and push container (ACR):
```bash
az acr create -n <acrName> -g <rg> --sku Basic
az acr build -r <acrName> -t bullethole-backend:latest multiplayer_node_server
```

2. Create Container App environment and app:
```bash
az containerapp env create -n <envName> -g <rg> -l <region>
az containerapp create -n bullethole-backend -g <rg> \
  --environment <envName> \
  --image <acrName>.azurecr.io/bullethole-backend:latest \
  --target-port 8080 --ingress external --query properties.configuration.ingress.fqdn
```

3. Use the returned FQDN in the app as:
- `Backend URL`: `https://<fqdn>`

Container Apps handles TLS; the app upgrades automatically to `wss://` for game socket.

## Azure CI/CD (Current Setup)

This repo uses two GitHub Actions workflows:

- `.github/workflows/azure-static-web-apps-brave-pond-03a16080f.yml`
  - builds Flutter web (`flutter build web --release`)
  - deploys `build/web` to Azure Static Web Apps
  - triggers only when frontend files change
- `.github/workflows/matchmaker-AutoDeployTrigger-ec9e000a-64af-40bb-850c-f7a973ad71e1.yml`
  - deploys `multiplayer_node_server/` source to Azure Container Apps
  - enforces single-instance scaling by default (`min=0`, `max=1`)
  - triggers only when backend files change

### Required GitHub repository secrets

- `AZURE_STATIC_WEB_APPS_API_TOKEN_BRAVE_POND_03A16080F`
- `MATCHMAKER_AZURE_CLIENT_ID`
- `MATCHMAKER_AZURE_TENANT_ID`
- `MATCHMAKER_AZURE_SUBSCRIPTION_ID`

### Optional GitHub repository variables

- `DEFAULT_BACKEND_URL`
  - Example: `https://matchmaker.<region>.azurecontainerapps.io`
  - Used at web build time so the app defaults to your deployed backend instead of localhost.
- `MATCHMAKER_MIN_REPLICAS`
  - Default: `0` (cheapest, allows scale-to-zero)
- `MATCHMAKER_MAX_REPLICAS`
  - Default: `1` (important for current in-memory match state)
- `MATCH_TTL_MS`
  - Optional backend env var for auto-expiring inactive matches

## Why this is seamless

- one hosted URL for both matchmaking and gameplay
- invite code flow, no manual room naming needed
- authoritative backend validates legal moves
- works globally anywhere both clients can reach HTTPS

## Production notes

This prototype is intentionally in-memory and single-instance.
For production scale and reliability you should add:
- Redis for match/session storage and pub/sub fanout
- stateless app replicas behind a load balancer
- auth/token-based player sessions
- reconnection + resume logic
- metrics/rate limits/abuse controls

`Node.js for matchmaking` is a good choice, but not mandatory. It is a practical fit due to mature WebSocket ecosystem, I/O performance, and easy horizontal scaling with Redis.
