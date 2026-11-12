# SnapLedger API — rules for this folder

Spring Boot 4 + Java 21 REST API for the SnapLedger app. These rules apply to every
change under `api/`, written by you or by any agent. Repo-wide rules (language, commits,
agent triage) live in the root `CLAUDE.md`.

**Source of truth for behavior:** [`docs/api-contract.md`](../docs/api-contract.md).
If code and contract disagree, stop and ask which one is wrong; fix both in the same change.
Decisions and their reasons: [`docs/decisions/`](../docs/decisions/).

## Stack

| Concern | Choice |
|---|---|
| Runtime | Java 21, Spring Boot 4, Maven wrapper (`./mvnw`) |
| Web | Spring Web MVC, Bean Validation, RFC 9457 `ProblemDetail` |
| Persistence | Spring Data JPA, PostgreSQL 17, Flyway, `ddl-auto=validate` |
| Security | Spring Security + OAuth2 Resource Server (JWT HS256), see ADR 0004 |
| Mapping | MapStruct (`componentModel = "spring"`) |
| Boilerplate | Lombok, limited (see below) |
| API docs | springdoc-openapi at `/docs` |
| Tests | JUnit 5, Mockito, AssertJ, Testcontainers (PostgreSQL) |

In `pom.xml` since Increment 1: `spring-boot-starter-oauth2-resource-server`,
`spring-boot-testcontainers`, `testcontainers-junit-jupiter`, `testcontainers-postgresql`
(versions from the Boot 4.1 BOM). **Not yet**: MapStruct (Increment 2), springdoc (Increment 4).
Add a dependency only in the change that first uses it. Do not add libraries that duplicate
something above.

Mockito is loaded as a Java agent by Surefire (`maven-dependency-plugin:properties` +
`argLine -javaagent:${org.mockito:mockito-core:jar}`), because JDK 21+ warns about, and future
JDKs block, its self-attach. When adding another `argLine` user (e.g. JaCoCo in Phase 4), use
`@{argLine}` so both survive. Running a single test from the IDE may need the same agent.

## Commands

```bash
java21                                   # alias in ~/.zshrc; the default java on this machine is 17
docker compose up -d                     # from repo root: PostgreSQL 17 (needs .env)
cd api
./mvnw -q compile                        # fast check
./mvnw test                              # all tests (Testcontainers needs Docker running)
./mvnw test -Dtest=ExpenseServiceTest    # one class
./mvnw spring-boot:run                   # run on http://localhost:8080 (reads ../.env)
```

## Package layout: by feature, not by layer

Base package `com.yulehohenfeld.snapledger`. Each feature owns all its layers, so opening one
folder shows the whole feature.

```
com.yulehohenfeld.snapledger
├── auth/            AuthController, AuthService, AccessTokenService, RefreshTokenService,
│                    RefreshToken, RefreshTokenRepository, RefreshTokenProperties,
│                    dto/ (RegisterRequest, LoginRequest, RefreshRequest, TokenResponse, AuthResponse)
├── user/            UserController, UserService, User, UserRepository, UserMapper, dto/
├── category/        CategoryController, CategoryService, Category, CategoryRepository,
│                    CategoryMapper, dto/
├── expense/         ExpenseController, ExpenseService, Expense, ExpenseRepository,
│                    ExpenseMapper, ExpenseSummaryService?, dto/
└── shared/
    ├── error/       GlobalExceptionHandler, ProblemFactory, Slugs (contract slugs as constants),
    │                ApiException (validates its slug) and its subclasses
    ├── security/    SecurityConfig (two chains, ADR 0005; strict JWT validation, ADR 0006),
    │                JwtProperties (+ AUDIENCE), @CurrentUserId, ProblemDetailAuthenticationEntryPoint,
    │                ProblemDetailAccessDeniedHandler, AuthPathNotFoundHandler (chain 1 → 404),
    │                ProblemResponseWriter (package-private)
    ├── validation/  Reusable constraints (e.g. max UTF-8 bytes)
    └── config/      CorsProperties, ClockConfig, other cross-cutting beans
```

- A feature may call another feature's **Service**, never its Repository.
- `shared/` never imports from a feature package.
- Create a sub-package only when a feature grows past ~8 files (start flat + `dto/`).
- Class names: `XController`, `XService`, `XRepository`, `XMapper`, `XRequest`, `XResponse`.
  Entity has no suffix (`Expense`).

## Layers: what each one may and may not do

Flow: `Controller → Service → Repository → Entity`. DTOs cross the HTTP boundary; entities never do.

**Controller** (thin)
- `@RestController`, maps the contract path, validates input with `@Valid`.
- Gets the user id **only** from the token: `@CurrentUserId UUID userId` (reads `sub` of the validated JWT).
- Calls one service method and returns a DTO (`ResponseEntity` only when status/headers
  differ from 200, e.g. `201 + Location`, `204`).
- **No** `try/catch`, no business rules, no repository imports, no entity in signatures.

**Service** (business rules)
- Constructor injection, `@Transactional` on public methods that write;
  `@Transactional(readOnly = true)` on reads.
- Every query is **scoped by `userId`**. Ownership is proven by the query itself
  (`findByIdAndUserId(...).orElseThrow(NotFoundException::new)`), never by loading and comparing afterwards.
- Throws domain exceptions (`NotFoundException`, `ConflictException`...), never builds HTTP responses.
- Uses an injected `Clock` for "now" so tests are deterministic.

**Repository**
- Spring Data JPA interfaces. Derived queries or `@Query` with JPQL/named parameters.
  No string-concatenated SQL.
- Methods that return user data take `userId` as a parameter.

**Entity**
- `UUID` id generated by the application, `BigDecimal` + `NUMERIC(12,2)` for money,
  `Instant` for timestamps, `LocalDate` for the expense date.
- Lombok: `@Getter` and `@NoArgsConstructor(access = PROTECTED)` only. No `@Data`,
  no `@Setter`, no `@EqualsAndHashCode` on entities (broken with lazy proxies). Change state
  through intention-revealing methods (`expense.update(...)`).
- Relationships are `LAZY`. No bidirectional mapping unless a use case needs it.

**DTO**
- Java `record`, with Bean Validation annotations on request records.
- Money fields are `BigDecimal` serialized as a **string** with 2 decimals (contract rule).
- A response never exposes internal fields (password hash, token hash, other users' ids).

**Mapper**
- MapStruct interface per feature. No hand-written `*MapperImpl`.

## Errors

- One `GlobalExceptionHandler` (`@RestControllerAdvice`) turns every exception into an
  RFC 9457 `ProblemDetail` with `type = urn:snapledger:problem:<slug>`.
  The slugs and statuses are listed in the contract; add new ones there first.
- Domain exceptions extend a base `ApiException(status, slug, detail)`.
- Validation errors add an `errors: [{field, message}]` property.
- `500` returns a generic detail. The exception is logged with a correlation id, and the
  class name, message and stack trace are **never** sent to the client.
- Security errors (missing/invalid token, access denied) use the same ProblemDetail
  format via a custom entry point and access-denied handler.

## Security rules (non-negotiable)

1. **Secrets only from environment variables.** Never a literal password, key or token in
   code, `application*.properties`, tests or logs. The app must not start without `JWT_SECRET`
   (≥ 256 bits), enforced by `@ConfigurationProperties` + `@Validated`.
2. **CORS** uses the explicit list in `CORS_ALLOWED_ORIGINS`. Never `*`, never `allowedOriginPatterns("*")`.
   Each entry must be an exact origin `http(s)://host[:port]` (no path, query, userinfo, no
   `null`); `CorsProperties` refuses to start otherwise. Blank = no browser origin allowed.
3. **User identity comes from the token.** No endpoint accepts `userId` in body, query or path.
4. **Another user's resource → 404**, identical to "does not exist".
5. **Passwords**: BCrypt (`PasswordEncoder` bean). Register: 8–72 **UTF-8 bytes** (bcrypt reads
   at most 72 bytes). Login: only not blank and max 72 bytes, so it never reveals the policy.
   Login failures return a single `invalid-credentials` error for unknown email and wrong password.
6. **Refresh tokens**: opaque, stored as SHA-256 hash, rotated on every use, reuse revokes the
   family (ADR 0002). Raw tokens are never logged or persisted.
7. **Stateless API**: `SessionCreationPolicy.STATELESS`, CSRF disabled (no cookie auth).
   **Two filter chains** (ADR 0005): chain 1 `/api/v1/auth/**` without the JWT filter (ignores
   `Authorization`; unlisted paths and wrong methods answer `404 not-found` without
   `WWW-Authenticate`); chain 2 everything else, public paths listed explicitly and the rest
   `authenticated()`. Never merge them back into one. Access tokens are validated strictly
   (ADR 0006): `aud = snapledger-api`, `sub` canonical UUID, `exp`/`iat` required, 5 s skew,
   injected `Clock`. Domain auth errors are `ApiException`s, never Spring `AuthenticationException`s.
8. **Logging**: never log passwords, tokens, `Authorization` headers, request bodies of `/auth/*`
   or receipt content. Log ids, not personal data. **Database errors (a DataAccessException, SQLException,
   Hibernate JDBCException or PersistenceException anywhere in the cause chain) are logged without their
   message or cause chain** (driver messages quote column values such as emails): only errorId,
   exception class and constraint name.
9. **AI key** (Phase 3) is read only by the backend (ADR 0003).
10. **No sensitive data in URLs.** Passwords, tokens and emails go in the body or headers,
    never in a path or query parameter (URLs end up in access logs and browser history).
11. **Request records with secrets** (`password`, `refreshToken`) override `toString()` to mask
    them. A record's default `toString()` prints every field.
12. **Validation errors** return `field` + `message` only, never the rejected value.
13. **Every id parameter is ownership-checked**, including filters (`?categoryId=`). Malformed
    parameters (bad UUID, bad `month`) return `400`, never `500`.

Any change touching `auth/`, `shared/security/`, `shared/config/`, `application*.properties`
or a migration that touches `users`/`refresh_tokens` must be reviewed by the
`security-reviewer` agent before it is considered done.

## Database and Flyway

- Migrations in `src/main/resources/db/migration`, named `V<n>__<snake_case_description>.sql`
  (`V1__create_users.sql`). Seed data also goes in migrations (`V3__seed_default_categories.sql`).
- **Never edit a migration that has been committed.** Fix forward with a new one.
- Tables and columns in `snake_case`, plural table names. `uuid` primary keys, `timestamptz`
  for instants, `numeric(12,2)` for money, `NOT NULL` by default.
- Every foreign key has an index. Uniqueness rules from the contract are enforced by
  constraints too (e.g. category name per user, case-insensitive).
- Hibernate never creates schema (`ddl-auto=validate`). If validation fails, write a migration;
  do not change the setting.

## Tests

Mirror the main package: `src/test/java/com/yulehohenfeld/snapledger/<feature>/...`.

| What | How |
|---|---|
| Service rules | Plain JUnit + Mockito, no Spring context (`XServiceTest`) |
| Controller contract (status, JSON shape, validation, ProblemDetail) | `@WebMvcTest` + `MockMvc`, service mocked (`XControllerTest`) |
| Repository queries, constraints, migrations | `@DataJpaTest` + Testcontainers PostgreSQL via `@ServiceConnection` (`XRepositoryTest`) |
| End-to-end flows (register → login → refresh → reuse) | `@SpringBootTest` + Testcontainers (`XIntegrationTest`) |

- Tests never point at a shared or real database. Only Testcontainers, through **one shared**
  `@TestConfiguration` with a `@ServiceConnection` PostgreSQL bean, imported by the tests that need
  it. Spring caches test contexts, so the container is reused by every test class that shares the
  same context instead of starting one per class.
- Tests never contain a literal secret: the JWT secret is generated randomly at test startup
  (`support/TestJwtSecret`).
- Every `@WebMvcTest` uses `@ImportSecurityStack` (SecurityConfig, the ProblemDetail handlers,
  `AuthPathNotFoundHandler`, `TestJwtSecret`) plus `@Import(ClockConfig.class)` or a fixed clock
  (see the `spring-patterns` skill). Test-only controllers are `@TestComponent` + `@Import`.
- Every ownership rule has a test proving another user gets `404`.
- Test names describe behavior: `returnsNotFoundWhenExpenseBelongsToAnotherUser`.

## Automatic checks (hooks)

`.claude/settings.json` registers two hooks that call `scripts/claude/api_rules.sh`:

- **PostToolUse** (`post_edit_hook.sh`): after every edit of a `.java` / `.properties` / `.yml`
  file under `api/`, checks that file. An ERROR blocks until it is fixed. Warnings are shown only.
- **Stop** (`stop_hook.sh`): before a response ends, checks every changed file, runs
  `./mvnw compile` when sources changed (Java 21), and, once per change set, requires the
  `security-reviewer` when auth, security config, properties, user/token migrations, `pom.xml`
  or env files changed.

Rules that need judgment stay with the `api-reviewer` agent. Before promoting a new rule to
ERROR, run the script on the whole `api/` and confirm the baseline is zero.

| Rule | Level | Checks |
|---|---|---|
| A1-FIELD-INJECTION | ERROR | `@Autowired` in main code (use constructor injection; tests may use it) |
| A2-SECRET-LITERAL | ERROR / WARNING | ERROR: `password`/`secret`/`api-key`/`credentials` property with a literal value instead of `${...}`. WARNING: string literal assigned to a secret-like name in Java |
| A3-CORS-WILDCARD | ERROR | `"*"` passed to CORS origin configuration |
| A4-TRY-IN-CONTROLLER | ERROR | `try {` inside a `*Controller.java` |
| A5-REPO-IN-CONTROLLER | ERROR | Controller imports a `*Repository` |
| A6-FLOATING-MONEY | ERROR | `double`/`float`/`Double`/`Float` for amount/total/price fields |
| A7-DDL-AUTO | ERROR | `ddl-auto` set to anything other than `validate` |
| A8-USERID-FROM-REQUEST | ERROR | `userId` taken from `@RequestBody`/`@RequestParam`/`@PathVariable` or a request record |
| A9-SYSOUT | WARNING | `System.out` / `System.err` / `printStackTrace()` |
| A10-LOMBOK-DATA-ENTITY | ERROR | `@Data` or `@Setter` on an `@Entity` |

A rule that can be checked by grep belongs in the script, not only in this file.

## Working agreement

- Before writing code, state: "This goes in `<Class>` because it is responsible for `<rule>`.
  Does it break a layer rule? No." If unsure where logic belongs, **ask**.
- Never invent an endpoint, field or error not in the contract. Propose a contract change instead.
- Follow the pattern of the closest sibling feature. Consistency beats local cleverness.
- Commit scope for this folder: `feat(api)`, `fix(api)`, `test(api)`, `refactor(api)`, `chore(api)`.
