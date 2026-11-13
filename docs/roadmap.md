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
- [ ] App foundation: `app/CLAUDE.md`, MVVMC rules and hooks, app agent and skill

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
- [ ] Step 3, required: database `lock_timeout` (connection level, e.g. `SET lock_timeout = '3s'`) so a stalled family lock cannot hold pool connections forever; a timeout stays a masked `500`, never `401 invalid-refresh-token` (it would wipe a healthy session); test that holds the lock past the timeout
- [ ] Step 3, required: `RefreshTokenService.rotate` calls `lockActive` before `markUsed`/insert, `noRollbackFor` on reuse, and a service-level integration test "reuse revokes the family and the newest token fails" (ADR 0008)
- [ ] Pin `org.hibernate.orm.jdbc.extract` to `INFO` (at `TRACE` it logs values read back: emails, password hashes), with a positive-control test; check `org.hibernate.orm.results` the same way
- [ ] Name made only of no-break spaces (U+00A0, U+2007, U+202F) passes `@NotBlank`: require at least one visible character
- [ ] Owner decision: allow ZWJ/ZWNJ (U+200D/U+200C) in names only between visible characters (Persian/Indic names, composed emoji); every other format character stays rejected
- [ ] `POST /auth/register`, `/auth/login`, `/auth/refresh`, `/auth/logout`
- [ ] `GET /users/me`, `PATCH /users/me`
- [ ] springdoc at `/docs`
- [ ] Tests: the "must exist" list in the `auth-flow` skill

**App**
- [ ] Dependencies: provider, go_router, dio, flutter_secure_storage
- [ ] `API_BASE_URL` via `--dart-define`, `ApiClient`, `AuthInterceptor` with single-flight refresh and session wipe
- [ ] Session state + GoRouter `redirect` (no static navigation state)
- [ ] Screens: login, register; shell with bottom navigation (Summary, Expenses, Profile)
- [ ] Profile: show user, change name/currency, logout
- [ ] Tests: interceptor (concurrent 401s → one refresh), ViewModels and Controllers

**Done when:** register → use the app → wait for the access token to expire → keep using it
→ logout works, on Android, iOS and Web, and `security-reviewer` reports no critical or high findings.

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

## Phase 4 — Quality, CI and deploy

Goal: anyone can see the project build, test and run in public.

- [ ] GitHub Actions: API (`./mvnw verify` with Testcontainers) and app (`flutter analyze`, `flutter test`) on every push and PR
- [ ] Coverage report and minimum threshold for the API services and the app ViewModels
- [ ] End-to-end test of the auth flow against a running API
- [ ] Rate limiting on `/auth/*` (`429 too-many-requests`) and on receipt scans; `/auth/register` too (its `409` reveals registered emails) and `/auth/refresh` bounded per family as well as per IP (concurrent refreshes of one family queue on its row lock, each holding a pool connection)
- [ ] Scheduled cleanup of expired refresh tokens
- [ ] API container image; deploy API + managed PostgreSQL (HTTPS only, HSTS)
- [ ] Deploy the Flutter Web build; `/docs` disabled or protected in production
- [ ] README badges (build, coverage) and a live demo link

**Done when:** a recruiter can open the live demo, create an account and use every feature,
and every push to `main` is built and tested automatically.

## Later (ideas, not committed)

- Email verification, password reset and change, account deletion
- Recurring expenses, budgets per category with alerts
- CSV export, multi-currency with conversion
- Offline mode with sync
- List of active sessions with remote logout
