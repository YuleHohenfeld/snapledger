# SnapLedger app

The Flutter client of SnapLedger (iOS, Android, Web). Architecture: MVVMC with Provider,
organized by feature → screen → layer ([ADR 0010](../docs/decisions/0010-app-architecture-mvvmc-provider.md)).

- Project overview and full local setup (database + API): [root README](../README.md)
- Rules for this folder (layers, session security, tests, hooks): [`app/CLAUDE.md`](CLAUDE.md)
- What the API offers: [`docs/api-contract.md`](../docs/api-contract.md)

## Run

Start the API first (see the root README), then:

```bash
cd app
flutter pub get
flutter run --dart-define=API_BASE_URL=http://localhost:8080          # iOS simulator / desktop
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8080           # Android emulator
flutter run -d chrome --web-port 8081 \
  --dart-define=API_BASE_URL=http://localhost:8080                    # Web (port allowed by CORS)
```

`API_BASE_URL` is required; `http://` is for local development only.

## Check

```bash
flutter analyze   # must report "No issues found!"
flutter test
```
