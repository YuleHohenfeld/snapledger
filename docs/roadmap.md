# Roadmap

SnapLedger is built in phases. Each phase ends with something that **works end to end** and
is demoable. Tests ship **with** each feature (golden rule 6 in the root `CLAUDE.md`);
Phase 4 adds the cross-cutting quality layer (CI, coverage gates, end-to-end tests).

Legend: `[x]` done · `[ ]` to do

## Phase 0 — Foundation ✅

Documentation, configuration and tooling, with no feature code yet.

- [x] API contract v1 ([`api-contract.md`](api-contract.md))
- [x] ADRs: refresh token rotation (0002), AI key in the backend (0003), JWT via resource server (0004)
- [x] Local PostgreSQL 17 with Docker Compose, `.env.example`, hardened `.gitignore`
- [x] API configuration from environment variables, Flyway owns the schema
- [x] Rules for Claude (`CLAUDE.md`, `api/CLAUDE.md`), agents, skills and hooks
- [x] README, architecture overview, ADR 0001 (monorepo), MIT license
- [x] Root `CLAUDE.md` with agent triage; planner and implementer agents
- [x] App foundation: `app/CLAUDE.md`, MVVMC rules and hooks (`mvvmc_rules.sh`, `flutter analyze` in the Stop hook), `mvvmc-reviewer` agent, `mvvmc-patterns` skill, app security checklist, stricter analysis options, ADR 0010

## Phase 1 — Authentication

Goal: a user can register, log in, stay logged in for weeks, and log out. Their session
survives an expired access token without noticing.

**API**
- [x] Dependencies: OAuth2 Resource Server, Testcontainers *(Increment 1)*
- [x] Dependencies: MapStruct *(Increment 2)*
- [ ] Dependencies: springdoc *(Increment 4)*
- [x] `JwtProperties` with fail-fast validation *(Increment 1)*
- [x] `RefreshTokenProperties` *(Increment 2)*
- [x] `SecurityConfig` (two chains, ADR 0005; strict JWT validation, ADR 0006), CORS from `CORS_ALLOWED_ORIGINS`, ProblemDetail entry point and handlers *(Increment 1)*
- [x] `GlobalExceptionHandler` + `ApiException` hierarchy *(Increment 1)*
- [x] Error dispatch: container errors forwarded to `/error` must keep their real status in the ProblemDetail format instead of becoming `401` for anonymous callers (otherwise a server error can trigger a needless refresh and log the user out). Needs an `ErrorController` and a real-port test *(start of Increment 2; ADR 0007)*
- [x] Exception traversal hardening in `GlobalExceptionHandler`: one identity-set walk over causes **and suppressed exceptions** (a database error attached with `addSuppressed` must also be masked in logs; a cause cycle A→B→A must not loop forever) *(start of Increment 2; lives in `InternalErrors`)*
- [x] Positive control test for `signRawPayload` in `SecurityConfigTest` (a valid hand-signed token returns 200), so the null-`iat` test cannot pass for the wrong reason *(start of Increment 2)*
- [x] Failures after commit inside MVC logged once, masked, with nothing glued to the sent body; client disconnects as one `DEBUG` line instead of an `ERROR` with stack trace *(start of Increment 2; ADR 0007 points 6–7)*
- [x] Defense in depth: pin `org.springframework.web.servlet.mvc.support.DefaultHandlerExceptionResolver` to `ERROR` in `logback-spring.xml`, with a guard test. Its `WARN` lines print the exception unmasked (and a raw newline allows log forging); they are reached only when one of our `@ExceptionHandler`s fails with something that is not a client disconnect *(start of Increment 2 Step 2)*
- [ ] Follow-up, with the first streaming endpoint: committed-response check (`abortIfCommitted` + rethrow) in `handleApi` and `handleConstraintViolation` *(ADR 0007 point 6)*
- [ ] Follow-up, with the first streaming endpoint: revisit the unmasked `DispatcherServlet` `DEBUG` line "Failed to complete request" for committed database failures *(ADR 0007 point 5, residual risk)*
- [ ] Hygiene: `resetBuffer()` before `setStatus(500)` when the client disconnects before commit, so no buffered partial body survives
- [x] Migrations: `users`, `refresh_token_families`, `refresh_tokens`, with entities, repositories, request/response records and validation constraints; the family row serializes rotation and revocation *(Increment 2 Step 2; ADR 0008)*
- [x] Database `lock_timeout = 3s` on every pool connection (pgjdbc startup option) so a stalled family lock cannot hold pool connections forever; a timeout stays a masked `500`, never `401 invalid-refresh-token` (it would wipe a healthy session); tests hold a family lock and a duplicate-email insert past the timeout *(Increment 2 Step 3)*
- [x] Increment 3, required: `RefreshTokenService.rotate` calls `lockActive` before `markUsed`/insert, `noRollbackFor` on reuse, never catches the lock timeout, and a service-level integration test "reuse revokes the family and the newest token fails" (ADR 0008 and its amendment) *(Increment 3)*
- [x] Pin `org.hibernate.orm.jdbc.extract` to `INFO` (at `TRACE` it logs values read back: emails, password hashes), with a positive-control test; `org.hibernate.orm.results` checked (no values). Found on the way: `org.hibernate.orm.core` at `DEBUG` lists every entity's fields after a flush, so it is pinned to `INFO` too *(Increment 2 Step 3; ADR 0007 point 5)*
- [x] Hash the password before opening register's transaction (`TransactionTemplate`), so a pool connection is not held during bcrypt *(Increment 2 Step 3; ADR 0009)*
- [x] ADR 0009: plain bcrypt with pinned cost 10, hashing outside the transaction, `lock_timeout = 3s` (also fine for Flyway) *(Increment 2 Step 3)*
- [x] Hook rule A11: only `ContainerErrorDispatchIntegrationTest` may use a real port (a second Tomcat is `Tomcat-1` and escapes the logger pin, ADR 0007) *(Increment 2 Step 3)*
- [ ] Bcrypt cost change (when Phase 4 rate limiting allows a higher cost): `upgradeEncoding` checked on successful login with re-hash and update; accept and document the timing gap between old-cost accounts and the new-cost dummy hash during the transition (ADR 0009)
- [ ] Next migration that touches `users`: tighten `ck_users_password_hash_bcrypt` to plain bcrypt (no `{bcrypt}` prefix), or switch to `DelegatingPasswordEncoder` instead (ADR 0009)
- [ ] Optional: `ApiException` carries extra response headers, so `handleApi` stops comparing the slug to add `WWW-Authenticate: Bearer`
- [ ] Tests: a shared base (or meta-annotation) for integration tests so every `@SpringBootTest` reuses one cached context and one PostgreSQL container
- [ ] Hygiene: migrate the remaining long comments in `shared/` and in tests to the code-notes format (short bilingual line + `Notes:` link)
- [ ] Name made only of no-break spaces (U+00A0, U+2007, U+202F) passes `@NotBlank`: require at least one visible character
- [ ] Owner decision: allow ZWJ/ZWNJ (U+200D/U+200C) in names only between visible characters (Persian/Indic names, composed emoji); every other format character stays rejected
- [x] `POST /auth/register` (atomic, `409` by constraint name), `POST /auth/login` (no enumeration, dummy hash), `PasswordEncoder` with pinned cost, `AccessTokenService`, `RefreshTokenService.startFamily` *(Increment 2 Step 3)*
- [x] `POST /auth/refresh`, `/auth/logout` (rotation, reuse revokes the session, logout revokes the session of any known token, lock timeout stays a masked `500`) *(Increment 3)*
- [ ] Absolute session lifetime: today rotation renews a session forever. Cap a family at a fixed age (e.g. 90 days from `refresh_token_families.created_at`), checked in `rotate` right after `lockActive`, like token expiry: `401 invalid-refresh-token`, **no** revocation. Needs a new ADR (RFC 9700 §4.14) and a contract note
- [ ] Optional hygiene: the reuse `WARN` is written before `rotate` commits, so a failed commit would leave a "family revoked" line for a revocation that never happened; log after commit (e.g. `TransactionSynchronization.afterCommit`)
- [x] `GET /users/me` (`401 unauthorized` + `WWW-Authenticate: Bearer` when the user is gone) *(Increment 2 Step 3)*
- [ ] `PATCH /users/me`
- [ ] springdoc at `/docs`
- [ ] Tests: the "must exist" list in the `auth-flow` skill

**App**
- [x] Dependencies: provider, go_router, dio, flutter_secure_storage, flutter_localizations + intl (each with its first use)
- [x] i18n: `l10n.yaml`, `app_en.arb`, `AppLocalizations` wired in the root widget
- [x] `API_BASE_URL` via `--dart-define`, `ApiClient`, `AuthInterceptor` with single-flight refresh and session wipe
- [x] Session state + GoRouter `redirect` (no static navigation state)
- [x] Screens: login, register, splash; shell with bottom navigation (Summary, Expenses, Profile)
- [x] Profile: show user, logout
- [ ] Profile: change name/currency (needs `PATCH /users/me`)
- [ ] Android 12+ device-to-device transfer: add `android:dataExtractionRules` excluding the secure-storage files from `cloud-backup` and `device-transfer` (`allowBackup=false` alone does not cover transfer); confirm a restore error lands on signed out, not a crash
- [ ] Router: accept only the exact tab paths in `redirectFor` (or an `errorBuilder` back to `/summary`) until tab sub-routes exist, so `/summary/x` never shows go_router's default error page
- [ ] Keep `?from=` when going from login to register (today `goTo(register)` drops the deep-link return target)
- [ ] Android debug network config: also allow `127.0.0.1` (AppConfig accepts it) or reject it in AppConfig on Android
- [ ] `LoginController`: decide the password clear from `viewModel.state` after `await submit` instead of listening to the ViewModel; `ProfileViewModel.logout`: reset `_loggingOut` in `finally`
- [ ] Run the project formatter config consistently (`dart format` with the project page width) before commits, so diffs carry no formatting noise
- [ ] Tests: interceptor (concurrent 401s → one refresh), ViewModels and Controllers
- [ ] Serialize `TokenStore` storage calls (read/write/delete) with a small mutex, so a sign-in, a wipe and a refresh can never interleave their keychain operations (the epoch and write ticket cover today's known races; ADR 0011)
- [x] Step 3, before the first Android release: `android:allowBackup="false"` or `dataExtractionRules` / `fullBackupContent` excluding the secure storage file (ADR 0011 open item, with `security-reviewer`)
- [ ] Prerequisite of the web build: the `TokenStore` mutex above (web storage writes can finish out of order, so the write ticket's ordering assumption does not hold there); also closes a narrow fail-safe case where a retried pending delete could erase a just-written sign-in token
- [ ] `AuthInterceptor`: record `_tokens.epoch` in `onRequest` and never retry a 401 whose request was sent under another session (a request sent as account A must not be replayed as account B after a sign-out/sign-in)
- [ ] `TokenStore.save`: if a `clear()` ran during the sign-in write, do not expose the access token nor report signedIn (today it ends at the next refresh; functional only)
- [ ] Web build: document that browsers follow redirects themselves (`followRedirects: false` has no effect there; the Fetch spec drops `Authorization` on cross-origin redirects)
- [x] Step 3: rename `test/widget_test.dart` to mirror `lib/app/` once the composition root exists
- [ ] Optional: make the `core/session` ↔ `core/api` dependency one-way (today `SessionNotifier` imports `TokenResponse` from `core/api/`, and `core/api/` imports `core/session/`); e.g. move `TokenResponse` or have `signIn` take the two token strings

**Done when:** register → use the app → wait for the access token to expire → keep using it
→ logout works, on Android, iOS and Web, and `security-reviewer` reports no critical or high findings.

## Phase 1.5 — Account recovery

Goal: a user who forgot the password can set a new one, and can verify the account email.
Next in line after the Phase 1 app (planner first).

- [ ] Plan, ADRs (code format and limits, email sending), contract changes
- [ ] API: forgot password and reset with a single-use, hashed, short-lived code (always `202`, revokes every session on reset), email verification code, attempt limits on these endpoints
- [ ] Local email capture with Mailpit in `docker-compose.yml` (codes visible at `localhost:8025`)
- [ ] App: forgot password, reset with the code, verify email screens

## Phase 2 — Expenses and monthly summary

Goal: record expenses by category and understand where the money went each month.

**API**
- [ ] Migrations: `categories` (with default seed), `expenses`
- [ ] Categories CRUD (defaults read-only, `409 category-in-use`, unique names)
- [ ] Expenses CRUD with `?month=` and `?categoryId=` filters
- [ ] `GET /expenses/summary?month=` (totals, per category, previous month)
- [ ] Tests: ownership `404` for every id parameter, money rounding, empty month

**App**
- [ ] Expenses tab: month selector, list, create/edit/delete form
- [ ] Categories management (from the expense form and the profile)
- [ ] Summary tab: total, comparison with the previous month, chart per category
- [ ] Money input and formatting per user currency
- [ ] Tests: ViewModels and Controllers of each screen

**Done when:** a month of real expenses can be entered and the summary matches the sum of
the list, to the cent.

## Phase 3 — AI receipt scanning

Goal: take a photo of a receipt and get a pre-filled expense to confirm.

- [ ] ADR: AI provider and model choice, cost limits
- [ ] Contract: `POST /receipts/scan` (multipart) → draft `ExpenseRequest` + confidence
- [ ] API: `ReceiptExtractor` port + provider adapter, upload validation (type by magic bytes,
      5 MB), per-user daily limit, no image storage, no content in logs (ADR 0003)
- [ ] App: camera/gallery picker, upload with progress, pre-filled form, manual fallback on failure
- [ ] Tests: extractor faked in API tests; malformed AI output handled; limit enforced; a client
      that aborts the upload leaves one `DEBUG` line, not an `ERROR` (ADR 0007 point 7)

**Done when:** a photo of a real receipt produces a correct draft most of the time, and a
failed scan never blocks manual entry.

## Phase 4 — Quality, CI and demo

Goal: anyone who finds the repository can see it build, test and run, without a production
deploy. SnapLedger is a portfolio project, not a launched product.

- [ ] GitHub Actions: API (`./mvnw verify` with Testcontainers) and app (`flutter analyze`, `flutter test`) on every push and PR
- [ ] Coverage report and minimum threshold for the API services and the app ViewModels
- [ ] End-to-end test of the auth flow against a running API
- [ ] Rate limiting on `/auth/*` (`429 too-many-requests`) and on receipt scans; `/auth/register` too (its `409` reveals registered emails) and `/auth/refresh` bounded per family as well as per IP (concurrent refreshes of one family queue on its row lock, each holding a pool connection)
- [ ] Scheduled cleanup of expired refresh tokens: delete **whole families** (revoked, or with every token expired), never single used token rows of an active family. A deleted used row makes its reuse look like an unknown token (`401` without revoking the session), so reuse detection silently breaks (ADR 0002)
- [ ] One-command demo: `docker compose --profile demo up` runs PostgreSQL, the API image, the Flutter Web build (served by nginx on `localhost:8081`) and Mailpit; only Docker needed
- [ ] README for visitors: GIFs of the main flows, a 1–2 minute video, badges (build, coverage), "run the demo" section
- [ ] Optional: a free hosted demo (web app on a static host, API + database on a free tier) with a "demo data" notice and periodic reset; needs rate limiting and a real email provider or an on-screen code for the demo

**Done when:** someone who clones the repository runs one command and uses every feature in
the browser, the README shows the app working without running anything, and every push is
built and tested automatically.

## Later (ideas, not committed)

- Password change while signed in, account deletion
- Recurring expenses, budgets per category with alerts
- CSV export, multi-currency with conversion
- Offline mode with sync
- List of active sessions with remote logout
