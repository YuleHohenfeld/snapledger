# 0010. App architecture: MVVMC with Provider, GoRouter, Dio and secure storage

- Status: Accepted
- Date: 2026-11-13

## Context

The Flutter app (iOS, Android, Web) is about to get its first screens: login, register, a shell
with three tabs (Summary, Expenses, Profile), then expense forms and a chart. It has to:

- keep a session alive across expired access tokens with **one** refresh at a time and wipe the
  session when the refresh token is rejected (contract, [ADR 0002](0002-refresh-token-rotation.md));
- keep tokens out of plain storage and logs;
- stay testable without a device: most rules should be checked by plain Dart tests;
- be readable by a reviewer of a public portfolio, and by AI agents that follow written rules.

Flutter does not impose an architecture. Without one, screens grow into large `StatefulWidget`s
that mix layout, HTTP calls, parsing and navigation, which is hard to test and to review.

## Decision

1. **MVVMC**, with a one-way flow `View → Controller → ViewModel → Repository → Model`:
   - **View**: widgets only; reads state, forwards events.
   - **Controller**: screen-only state (text and focus controllers, form keys), `dispose`,
     navigation intents through an `AppNavigator` interface.
   - **ViewModel**: business state of one screen as a `ChangeNotifier`, importing only
     `package:flutter/foundation.dart`, so it is tested with plain `test()`.
   - **Repository**: the only layer that calls the API (through one `ApiClient`), mapping JSON
     to immutable models and ProblemDetail to typed failures.
2. **Provider + ChangeNotifier** for dependency injection and state: app-wide objects in one
   composition root, ViewModels scoped to their screen.
3. **GoRouter** with a `redirect` driven only by the session state, `StatefulShellRoute` for the
   tabs, typed locations, no global navigator keys.
4. **Dio** with an `AuthInterceptor` that attaches the Bearer token and runs a single-flight
   refresh on `401 unauthorized` (never on `/auth/*`), wiping the session on
   `401 invalid-refresh-token`.
5. **flutter_secure_storage** (Keychain / Keystore) is the only place tokens are persisted.
6. **Layout by feature → screen → layer** (`features/<feature>/<screen>/{application,presentation}`
   plus `_shared/data`), with `core/` for cross-cutting code that never imports a feature.
7. **i18n from the first screen**: English strings in `app_en.arb` through `gen-l10n`
   (`flutter_localizations` + `intl`); Portuguese is added later as another `.arb` without
   touching widgets.
8. **Dependencies arrive with their first use** (as in the API), and grep-checkable rules are
   enforced by hooks (`scripts/claude/mvvmc_rules.sh`, rules D1–D11 in `app/CLAUDE.md`).

## Consequences

- Each layer has one reason to change and one kind of test: ViewModels and Controllers with
  fakes, repositories and the interceptor with a fake HTTP adapter, pages with widget tests.
- The Controller layer adds one class per screen. For trivial screens it can feel like
  ceremony; the payoff is that ViewModels never touch `TextEditingController` or `BuildContext`,
  which is what keeps them testable without Flutter.
- `ChangeNotifier` notifies all listeners; pages must use `context.select` to avoid rebuilding
  more than needed.
- Provider is resolved at runtime: a missing provider fails when the screen opens, not at
  compile time. Widget tests for every page catch it early.
- Session security depends on one class (`AuthInterceptor`) and one store; both are on the
  `security-reviewer`'s mandatory list.
- On the web, secure storage still ends up in `localStorage` (encrypted with WebCrypto), so XSS
  remains a risk; the web build keeps the access token short-lived and in memory.

## Alternatives considered

- **MVVM without a Controller**: fewer classes, but text controllers, focus and navigation end
  up in the ViewModel (which then needs Flutter widgets) or in the widget (which then holds
  logic). Rejected: the split between screen state and business state is the point.
- **BLoC / Cubit**: strong and popular, explicit events and streams. More boilerplate per
  screen and a second paradigm (streams) for a small app; its testability is matched here by
  plain `ChangeNotifier` ViewModels. Rejected for v1.
- **Riverpod**: compile-safe providers and no `BuildContext` for reads. A larger concept surface
  (provider kinds, code generation, auto-dispose rules) than this project needs, and Provider is
  the option recommended in Flutter's own state-management guide. Rejected for v1; migrating is
  possible screen by screen if it ever pays off.
- **GetX**: routing, DI and state in one package with global access. Global state and implicit
  context make testing and reviewing harder. Rejected.
- **Plain `setState`**: fine for widgets, but business state, HTTP and navigation would live in
  `State` classes that can only be tested as widgets. Rejected as the architecture (still used
  for purely visual local state inside a widget).
- **`Navigator` 2.0 by hand** instead of GoRouter: full control, much more code for redirects,
  deep links and nested tabs. Rejected.
- **`http`** instead of Dio: smaller, but interceptors, retry and test adapters would be written
  by hand. Rejected.
- **`shared_preferences`** for tokens: plain text on disk. Rejected for anything secret.

## References

- [Flutter: app architecture guide](https://docs.flutter.dev/app-architecture)
- [Flutter: state management options](https://docs.flutter.dev/data-and-backend/state-mgmt/options)
- [OWASP MASVS](https://mas.owasp.org/MASVS/) (MASVS-STORAGE, MASVS-NETWORK, MASVS-AUTH)
- [RFC 9700: OAuth 2.0 Security Best Current Practice](https://www.rfc-editor.org/rfc/rfc9700) (refresh token rotation)
