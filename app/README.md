# SnapLedger app

The Flutter client of SnapLedger (iOS, Android, Web). Architecture: MVVMC with Provider,
organized by feature → screen → layer ([ADR 0010](../docs/decisions/0010-app-architecture-mvvmc-provider.md)).

- Project overview and full local setup (database + API): [root README](../README.md)
- Rules for this folder (layers, session security, tests, hooks): [`app/CLAUDE.md`](CLAUDE.md)
- What the API offers: [`docs/api-contract.md`](../docs/api-contract.md)

## After cloning

`lib/l10n/gen/` (the generated `AppLocalizations`) is not committed. `flutter pub get` creates
it from `lib/l10n/app_en.arb`; run `flutter gen-l10n` after editing an `.arb` file if your IDE
does not regenerate it. Until then, `flutter analyze` reports missing imports.

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

## Run against the local API

1. From the repository root start the database: `docker compose up -d`.
2. Start the API (Java 21): `cd api && ./mvnw spring-boot:run`.
3. Run the app with the address that reaches your machine from where the app runs:

| Where the app runs | `API_BASE_URL` | Why |
|---|---|---|
| Android emulator | `http://10.0.2.2:8080` | `10.0.2.2` is the emulator's alias for the host machine; `localhost` would be the emulator itself |
| iOS simulator | `http://localhost:8080` | The simulator shares the host's network |
| Chrome | `http://localhost:8080`, with `flutter run -d chrome --web-port 8081` | The API only allows the origin `http://localhost:8081` (CORS) |

Plain `http://` works only in debug builds: Android allows it just for `10.0.2.2` and `localhost`
(`android/app/src/debug/res/xml/network_security_config.xml`, debug source set only), and the app
itself refuses `http://` in release builds or for any other host.

**iOS note.** `Info.plist` has no App Transport Security exception yet: test the simulator first,
because loopback `http://localhost` may work without one. If the simulator refuses it, add a
debug-only exception (never in a release build) and have the `security-reviewer` look at it. For
example, in `ios/Runner/Info.plist`:

```xml
<key>NSAppTransportSecurity</key>
<dict>
  <key>NSAllowsLocalNetworking</key>
  <true/>
</dict>
```

`NSAllowsLocalNetworking` allows cleartext only to local addresses, not to the internet. Because
`Info.plist` is shared by every build type, keep this change out of the commit that ships a release
(or use a separate debug `.xcconfig`/plist).

**Manual test script** (the real app against the real API):

1. Register a new account: you land on the Summary tab with the bottom bar.
2. Profile tab: name, email and currency are shown. Tap **Sign out**: you return to Sign in.
3. Sign in with the same account: you land on the Summary tab again.
4. Sign out, then sign in with a wrong password: "Email or password is incorrect.", and the password
   field is cleared.
5. Register again with the same email: "This email is already registered." under the email field.
   Editing the email clears the message.
6. Sign in, kill the app (swipe it away) and reopen: you stay signed in (the splash shows briefly).
7. Optional: stop the API and reopen the app signed in: the splash offers **Try again** and
   **Sign in again**.

## Check

```bash
flutter analyze   # must report "No issues found!"
flutter test
```
