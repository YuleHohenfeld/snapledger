# SnapLedger app — rules for this folder

Flutter app (iOS, Android, Web) for SnapLedger. These rules apply to every change under
`app/`, written by you or by any agent. Repo-wide rules (language, comments, commits, agent
triage) live in the root [`CLAUDE.md`](../CLAUDE.md).

**Source of truth for behavior:** [`docs/api-contract.md`](../docs/api-contract.md).
If the app needs a field, error or endpoint the contract does not have, stop and propose a
contract change; never guess the API. Architecture decision:
[ADR 0010](../docs/decisions/0010-app-architecture-mvvmc-provider.md). Big picture:
[`docs/architecture.md`](../docs/architecture.md) section 4. Examples of every layer: the
`mvvmc-patterns` skill.

## Stack

| Concern | Choice | In `pubspec.yaml` |
|---|---|---|
| SDK | Flutter 3.47 stable, Dart `^3.13` | yes |
| Architecture | MVVMC: View → Controller → ViewModel → Repository → Model (ADR 0010) | — |
| State and DI | `provider` + `ChangeNotifier` | not yet (first screen) |
| Navigation | `go_router` with a `redirect` driven by the session | not yet (first screen) |
| HTTP | `dio`, one `ApiClient` + `AuthInterceptor` | not yet (auth feature) |
| Token storage | `flutter_secure_storage` (Keychain / Keystore) | not yet (auth feature) |
| i18n | `flutter_localizations` + `intl`, `gen-l10n` from `.arb` files; English first, Portuguese later as `app_pt.arb` | not yet (first screen) |
| Money | `decimal` (`Decimal.parse` of the contract's decimal string) | not yet (first money field) |
| Lints | `flutter_lints` + the stricter set in `analysis_options.yaml` | yes |
| Tests | `flutter_test`; hand-written fakes (no mocking library) | yes |

**Add a dependency only in the change that first uses it** (same rule as the API), and never a
library that duplicates one above (no Riverpod, BLoC, GetX, `http`, `shared_preferences` for
session data). Every new dependency is part of the security review (it ships inside the app).

## Commands

```bash
export PATH="$HOME/Documents/development/flutter/bin:$PATH"   # if `flutter` is not on PATH
cd app
flutter pub get
flutter analyze                     # must say "No issues found!"
flutter test                        # all tests
flutter test test/features/profile  # one folder

# Run against the local API (start it first: see the root README)
flutter run --dart-define=API_BASE_URL=http://localhost:8080        # iOS simulator, desktop
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8080         # Android emulator
flutter run -d chrome --web-port 8081 \
  --dart-define=API_BASE_URL=http://localhost:8080                  # Web; 8081 is in CORS_ALLOWED_ORIGINS
```

`API_BASE_URL` has **no default**: without it the app shows a configuration error instead of
silently calling a wrong server. `http://` is only for local development; every other
environment uses `https://`.

## Folder layout: feature → screen → layer

Package `snapledger`. Every import is a `package:snapledger/...` import (rule D6).

```
lib/
├── main.dart            reads AppConfig, runApp(SnapLedgerApp)
├── app/                 composition root: SnapLedgerApp (MaterialApp.router), app-wide providers
├── core/                cross-cutting code; NEVER imports from features/
│   ├── api/             ApiClient (Dio), AuthInterceptor, ApiFailure + ProblemType (ProblemDetail → typed)
│   ├── config/          AppConfig: API_BASE_URL from --dart-define (the only place with a URL)
│   ├── session/         SessionNotifier (signed in / out / unknown), TokenStore
│   ├── storage/         SecureStore: the only wrapper around flutter_secure_storage
│   ├── router/          GoRouter + redirect, AppRoute (typed locations), AppNavigator (interface)
│   ├── l10n/            failure → localized message, formatting helpers (money, dates)
│   └── design/          theme, spacing, shared widgets with no business logic
├── l10n/                app_en.arb (+ app_pt.arb later); gen/ is generated, never edited
└── features/
    └── expenses/
        ├── _shared/data/
        │   ├── models/          ExpenseModel, ExpenseRequest (immutable, fromJson/toJson)
        │   └── repositories/    ExpenseRepository (interface) + ApiExpenseRepository
        ├── list/
        │   ├── application/
        │   │   ├── controller/  ExpenseListController
        │   │   └── viewmodel/   ExpenseListViewModel (+ its state classes)
        │   └── presentation/
        │       ├── page/        ExpenseListPage
        │       └── widgets/     widgets used only by this screen
        └── form/                same shape as list/
```

Features: `auth` (login, register), `profile`, `expenses`, `categories`, `summary`. The shell
with the bottom navigation (**Summary**, **Expenses**, **Profile**) lives in `core/router/`.

- `core/` never imports from `features/` (like `shared/` in the API). Wiring both together is the
  job of `app/` only.
- A screen's data lives in its feature's `_shared/data/` when two or more screens use it;
  a screen used alone may keep `data/` next to `application/`.
- A feature may import another feature's `_shared/data/` (models and repository interfaces),
  **never** its `application/` or `presentation/`. Expense form → `CategoryRepository` is fine.
- Files are `snake_case` of the class: `expense_list_page.dart`, `expense_list_view_model.dart`.
- Generated files (`*.g.dart`, `lib/l10n/gen/`) are never edited by hand and are skipped by
  analysis and hooks.

## Layers: what each one may and may not do

Flow: `View → Controller → ViewModel → Repository → ApiClient`, models flowing back. State
flows up through `notifyListeners()`; nothing calls "up" the chain.

**View** (`presentation/`: `XPage` and its widgets)
- Widgets only: layout, theme, reading state, forwarding user events to the Controller.
- Reads state with `context.watch<XViewModel>()` or, preferably, `context.select` for the one
  field it needs, so only that part rebuilds.
- Every user-facing string comes from `AppLocalizations.of(context)` (rule D9).
- **No** business logic, no `try/catch` around calls, no repository, `ApiClient` or `dio`
  import (D1), no `Navigator`/`GoRouter` calls of its own (navigation is a Controller intent).

**Controller** (`application/controller/`, `XController`)
- Owns **screen-only** state: `TextEditingController`s, `FocusNode`s, `GlobalKey<FormState>`,
  scroll controllers, "is the password visible". Created in the page's `State.initState` with
  `context.read`, released in `State.dispose` through `controller.dispose()`.
- Turns user events into ViewModel calls (`onSubmit()` → `viewModel.save(input)`) and turns
  ViewModel outcomes into **navigation intents** through `AppNavigator` (`navigator.goTo(AppRoute.expenses)`).
- Never stores a `BuildContext`, never holds business rules, never calls a repository.
- May import `package:flutter/widgets.dart` (text and focus controllers live there).

**ViewModel** (`application/viewmodel/`, `XViewModel`)
- `extends ChangeNotifier`; holds **business state** for one screen and exposes it as an
  immutable value (a `sealed` state class or final fields with `copyWith`), never a mutable list.
- From Flutter it imports **only** `package:flutter/foundation.dart` (D2): no `material`,
  `widgets`, `cupertino`, no `BuildContext`, no text controllers. It is testable with plain
  `test()` and a fake repository.
- Depends on repository **interfaces** received in the constructor; never creates them.
- Catches `ApiFailure` from repositories and turns it into state (a typed failure, never a
  message string: the View localizes it). Guards against `notifyListeners()` after `dispose()`.

**Repository** (`data/repositories/`, `XRepository` interface + `ApiXRepository`)
- The **only** layer that talks to the API, through `ApiClient` (D8). Paths, methods and
  payloads exactly as in the contract.
- Maps JSON ↔ models and lets `ApiClient` turn every ProblemDetail into a typed `ApiFailure`
  (`status`, `ProblemType` from the `type` URN slug, field errors, optional `errorId`).
- Never knows about widgets, l10n or navigation. Never logs request or response bodies.

**Model** (`data/models/`, `XModel`, `XRequest`)
- Immutable (`final` fields, `const` constructor where possible), `fromJson` / `toJson`,
  value equality when compared in tests.
- Money is `Decimal` parsed from the contract's **string** and written back with
  `toStringAsFixed(2)`; never `double` or `num` (D5). Dates: `DateTime` for timestamps
  (UTC, `DateTime.parse`), a date-only type or `yyyy-MM-dd` string for the expense date.
- JSON casts are explicit (`json['name'] as String`); `strict-casts` makes a missing cast an
  analyzer error. Unknown fields are ignored; missing required fields throw (a contract mismatch
  must fail loudly in tests).

## Dependency injection with Provider

- **App-wide** objects are created once in `lib/app/` (a `MultiProvider` above
  `MaterialApp.router`): `AppConfig`, `SecureStore`, `TokenStore`, `ApiClient`,
  `SessionNotifier` (`ChangeNotifierProvider`), the `GoRouter` and `AppNavigator`, and every
  repository as `Provider<XRepository>` (typed by the interface, so tests swap in fakes).
- **Screen-scoped** ViewModels are created by the screen's `XPage` with
  `ChangeNotifierProvider(create: (context) => XViewModel(context.read<XRepository>()))`; the
  provider disposes them when the screen leaves the tree. Never `ChangeNotifierProvider.value`
  with an object created in `build`.
- `context.read` in callbacks and `initState`; `context.watch`/`select` only in `build`.
- No service locators, no globals, no singletons with static state.

## Navigation

- One `GoRouter` (in `core/router/`), created in `lib/app/` with
  `refreshListenable: sessionNotifier` and a `redirect` that depends **only** on the session state:
  unknown → splash, signed out → `/login` (or `/register`), signed in and on an auth route →
  `/summary`. Tabs use `StatefulShellRoute.indexedStack`, so each tab keeps its state.
- Locations are typed (`AppRoute`), never string literals spread over screens.
- No `GlobalKey<NavigatorState>` or static router outside `core/router/` (D11); Controllers
  navigate through the `AppNavigator` interface, which tests fake.
- A redirect target taken from a link (`?from=`) is accepted only if it is an **internal**
  route of the app; anything else goes to `/summary` (no open redirects).

## Session and security (non-negotiable)

1. **Tokens only in `flutter_secure_storage`** through `SecureStore`/`TokenStore`. Never
   `shared_preferences`, files, `localStorage`, Hive or logs (D4). The access token may live in
   memory only; the refresh token is persisted. Passwords are never stored.
2. **`AuthInterceptor`** (the only code that sets `Authorization`, D10):
   - attaches `Bearer <accessToken>` to every request **except** `/auth/*`;
   - on `401` with `type` `unauthorized` from a non-`/auth/*` request: starts **one** refresh;
     every other request that fails meanwhile waits for the same future (single-flight), then
     each retries **once** with the new token (`extra` flag prevents a second retry);
   - a request that failed with a token older than the current one retries without refreshing;
   - refresh `401 invalid-refresh-token`, or a retried request answered `401` again → **wipe the
     session** (tokens and in-memory user) and the router redirects to login;
   - refresh failing with `500`, a timeout or no network → **no wipe** (the session may be
     healthy, contract: "the app may retry"); the original error goes to the caller;
   - never refreshes on a `401` from `/auth/*` (`invalid-credentials` is final);
   - the refresh call uses a separate `Dio` without the interceptor (no recursion).
3. **New tokens are persisted before they are used**: the rotated refresh token is the only
   valid one; losing it means logging in again.
4. **Logout**: call `POST /auth/logout` best effort with a short timeout, then wipe locally
   **regardless** of the result.
5. **Nothing sensitive in logs** (D3): no `print`/`debugPrint` in `lib/`; never log tokens,
   passwords, `Authorization` headers, request/response bodies of `/auth/*`, emails or amounts.
   A logger, when added, redacts these and is the only output.
6. **No secrets in the app.** The bundle is public (decompilable, and on the web it is plain
   JavaScript). `API_BASE_URL` comes from `--dart-define` and is read only in `core/config/`
   (D7); the AI key never reaches the app (ADR 0003).
7. **HTTPS outside local development.** Cleartext exceptions (Android network security config,
   iOS ATS) are debug-only and reviewed by `security-reviewer`.
8. **Web**: `flutter_secure_storage` on the web encrypts with WebCrypto but keeps the data in
   `localStorage`, so XSS can read it. Keep the access token short-lived and in memory, add no
   third-party scripts to `web/index.html`, and document the trade-off before shipping the web build.
9. **Input validation mirrors the contract** (lengths, email format, password bytes, amount
   format) for fast feedback; the API remains the authority.

Any change touching `lib/core/api/`, `lib/core/session/`, `lib/core/storage/`,
`lib/core/config/`, `lib/features/auth/`, `pubspec.yaml`, `AndroidManifest.xml`, `Info.plist`
or `web/index.html` must be reviewed by the `security-reviewer` agent before it is considered done.

## Errors

- `ApiClient` turns every non-2xx response into an `ApiFailure`: `ProblemType` from the slug of
  `urn:snapledger:problem:<slug>` (contract error table), `status`, `fieldErrors` for
  `validation-error`, `errorId` for `500`. `about:blank` and unknown slugs become
  `ProblemType.unknown` and the app branches on `status`. No network / timeout →
  `NetworkFailure`.
- The app branches on `status` and `type`, **never** on `title`/`detail` text, and **never shows
  server text** to the user: `core/l10n/` maps each `ProblemType` to an `AppLocalizations`
  message. `500` shows a generic message, optionally with the `errorId` for support.
- Field errors from `validation-error` are shown next to the matching field by name.

## Internationalization

- All user-facing text (labels, buttons, errors, semantics labels) comes from
  `AppLocalizations`; no literal strings in widgets (D9, warning). The product name
  `SnapLedger` is a brand, not translated.
- `lib/l10n/app_en.arb` is the template; keys are `camelCase` and grouped by screen
  (`loginTitle`, `expenseFormAmountLabel`). Portuguese arrives as `app_pt.arb`.
- Money and dates are formatted with `intl` using the user's currency and the device locale,
  never by string concatenation.

## Tests

Mirror `lib/`: `test/features/<feature>/<screen>/...`, `test/core/...`. Shared fakes
(`FakeExpenseRepository`, `FakeNavigator`, `FakeHttpAdapter`, `InMemorySecureStore`) live in
`test/support/`; test files never import each other.

| What | How |
|---|---|
| ViewModel rules and state transitions | plain `test()`, fake repository (`x_view_model_test.dart`) |
| Controller (text fields, submit, navigation intent, dispose) | plain `test()`, fake ViewModel dependencies + `FakeNavigator` |
| Repository (path, method, JSON, money string, ProblemDetail → `ApiFailure`) | real `ApiClient` + `Dio` with a fake `HttpClientAdapter` |
| `AuthInterceptor` | fake adapter: concurrent 401s → **one** refresh; `invalid-refresh-token` → wipe; retried 401 → wipe; refresh `500` → no wipe; `/auth/*` 401 → no refresh; no token in any log |
| Router redirect | unit test per session state, including the `?from=` allowlist |
| Pages | `testWidgets` with providers over fakes and the l10n delegates (`x_page_test.dart`) |

- No test calls a real server; no test contains a real token or password.
- Test names describe behavior: `'wipes the session when the refresh token is rejected'`.
- Every ViewModel that loads data has tests for loading, success and each failure it handles.

## Naming

| Kind | Class | File |
|---|---|---|
| Page | `ExpenseListPage` | `expense_list_page.dart` |
| Controller | `ExpenseListController` | `expense_list_controller.dart` |
| ViewModel and its state | `ExpenseListViewModel`, `ExpenseListState` | `expense_list_view_model.dart` |
| Repository | `ExpenseRepository` (interface), `ApiExpenseRepository` | `expense_repository.dart` |
| Response model | `ExpenseModel` | `expense_model.dart` |
| Request payload | `ExpenseRequest` | `expense_request.dart` |

## Comments

Same rule as the root `CLAUDE.md`: one short English line, its `PT:` translation, and the long
why in a note. In Dart:

```dart
/// Starts at most one refresh at a time; concurrent 401s await the same future.
/// PT: Inicia no máximo um refresh por vez; 401s concorrentes aguardam o mesmo future.
/// Notes: docs/code-notes/app-core.md#authinterceptor
```

App notes are named `docs/code-notes/app-<area>.md` (`app-core.md`, `app-auth.md`,
`app-expenses.md`...) and created with the first code that links to them.

## Automatic checks (hooks)

`.claude/settings.json` registers two hooks that call `scripts/claude/mvvmc_rules.sh`:

- **PostToolUse** (`post_edit_hook.sh`): after every edit of a `.dart` file under `app/`, checks
  that file. An ERROR blocks until it is fixed. Warnings are shown only.
- **Stop** (`stop_hook.sh`): before a response ends, checks every changed `.dart` file, runs
  `flutter analyze` when `lib/`, `test/`, `pubspec.yaml` or `analysis_options.yaml` changed
  (cached by content; skipped when Flutter is not found on `PATH`, in `$FLUTTER_ROOT` or in
  `~/Documents/development/flutter`), and, once per change set, requires the `security-reviewer`
  for the sensitive paths listed above.

Rules that need judgment stay with the `mvvmc-reviewer` agent. Before promoting a new rule to
ERROR, run the script on all of `app/lib` and `app/test` and confirm the baseline is zero.

| Rule | Level | Checks |
|---|---|---|
| D1-DATA-IN-VIEW | ERROR | A `presentation/` file imports a repository, `core/api/`, `dio` or `http` |
| D2-UI-IN-VIEWMODEL | ERROR | A ViewModel imports `material`/`widgets`/`cupertino`/`painting`/`rendering`, or uses `BuildContext` / `TextEditingController` |
| D3-PRINT | ERROR | `print(` / `debugPrint(` in `lib/` |
| D4-INSECURE-TOKEN-STORAGE | ERROR | `SharedPreferences`, `localStorage`, `sessionStorage` or Hive in a `lib/` file that mentions token, password or secret |
| D5-FLOATING-MONEY | ERROR | `double`/`num` for a name ending in amount, total, price, balance or percentage |
| D6-RELATIVE-IMPORT | ERROR | Relative `import`/`export` in `lib/` or `test/` (use `package:snapledger/...`) |
| D7-HARDCODED-URL | ERROR | `http://` / `https://` literal in `lib/` outside `lib/core/config/` |
| D8-HTTP-OUTSIDE-DATA | ERROR | `dio` or `http` imported in `lib/` outside `lib/core/api/` and `*/data/repositories/` |
| D9-HARDCODED-UI-TEXT | WARNING | `Text('...')` with a literal in a `presentation/` file (use `AppLocalizations`) |
| D10-AUTH-HEADER-OUTSIDE-INTERCEPTOR | ERROR | The `Authorization` header named in `lib/` outside `lib/core/api/` |
| D11-GLOBAL-NAVIGATION | ERROR | `GlobalKey<NavigatorState>` or a static `GoRouter` outside `lib/core/router/` |

`analysis_options.yaml` adds the compiler-level checks (strict casts, inference and raw types,
package imports, `avoid_print`, `unawaited_futures`, `use_build_context_synchronously`...).
A rule that can be checked by grep or by the analyzer belongs there, not only in this file.

## Working agreement

- Before writing code, state: "This goes in `<Class>` (View / Controller / ViewModel /
  Repository / Model) because it is responsible for `<rule>`. Does it break a layer rule? No."
  If unsure where logic belongs, **ask**.
- Never invent an endpoint, field or error not in the contract. Propose a contract change instead.
- Follow the closest sibling screen. Consistency beats local cleverness.
- `flutter analyze` with zero issues and the related tests green before reporting done.
- Commit scope for this folder: `feat(app)`, `fix(app)`, `test(app)`, `refactor(app)`, `chore(app)`.
