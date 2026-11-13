---
name: spring-patterns
description: Minimal, correct examples of every layer of the SnapLedger API (Spring Boot 4, Java 21) - Flyway migration, JPA entity, Spring Data repository scoped by userId, service with @Transactional and Clock, thin controller with current-user resolver, record DTOs (money as string, masked toString), MapStruct mapper, ApiException + GlobalExceptionHandler with ProblemDetail, and tests (Mockito, @WebMvcTest, @DataJpaTest + Testcontainers). Load when writing, planning or reviewing any code under api/, or when deciding "which layer does this belong to?".
---

# SnapLedger API patterns

Rules live in `api/CLAUDE.md`; this skill shows **how** to follow them. Examples use the
`expense` feature and are deliberately minimal. When real code exists, **the code wins**:
follow the sibling feature and report any divergence from this skill so it gets updated.

Imports are omitted unless they are not obvious. Spring Boot 4.1 / Spring 7 / Testcontainers 2
moved several classes; these were verified in this project:

| Class | Package |
|---|---|
| `@WebMvcTest` | `org.springframework.boot.webmvc.test.autoconfigure` |
| `@TestComponent` | `org.springframework.boot.test.context` |
| `OutputCaptureExtension` | `org.springframework.boot.test.system` |
| `PostgreSQLContainer` (no longer generic) | `org.testcontainers.postgresql` |
| `@MockitoBean` | `org.springframework.test.context.bean.override.mockito` |
| `@DataJpaTest` | `org.springframework.boot.data.jpa.test.autoconfigure` |
| `@AutoConfigureTestDatabase` | `org.springframework.boot.jdbc.test.autoconfigure` |
| `TestEntityManager` | `org.springframework.boot.jpa.test.autoconfigure` |
| `JsonMapper` (Jackson 3) | `tools.jackson.databind.json` |

If another import does not resolve, check the module for the Boot version in `pom.xml`
instead of changing the pattern, and add the verified package to this table.

## Where does it go?

| I need to... | Layer | File |
|---|---|---|
| Create or change a table, seed data | Migration | `resources/db/migration/V<n>__<what>.sql` |
| Map a table | Entity | `expense/Expense.java` |
| Query data (always with `userId`) | Repository | `expense/ExpenseRepository.java` |
| Business rule, transaction, ownership | Service | `expense/ExpenseService.java` |
| HTTP mapping, validation trigger | Controller | `expense/ExpenseController.java` |
| Request/response shape | DTO record | `expense/dto/ExpenseRequest.java`, `ExpenseResponse.java` |
| Entity ↔ DTO | Mapper | `expense/ExpenseMapper.java` |
| A new error case | `ApiException` subclass | `shared/error/` (slug must exist in the contract) |

## 1. Migration

```sql
-- V4__create_expenses.sql  (never edit after commit; fix forward with V5__...)
create table expenses (
    id           uuid          primary key,
    user_id      uuid          not null references users (id) on delete cascade,
    category_id  uuid          not null references categories (id),   -- RESTRICT: backs the 409
    amount       numeric(12,2) not null check (amount > 0),
    description  varchar(120)  not null,
    expense_date date          not null,
    created_at   timestamptz   not null,
    updated_at   timestamptz   not null
);

create index idx_expenses_user_date on expenses (user_id, expense_date desc);
create index idx_expenses_category  on expenses (category_id);
```

## 2. Entity

```java
@Entity
@Table(name = "expenses")
@Getter
@NoArgsConstructor(access = AccessLevel.PROTECTED) // JPA only
public class Expense extends AssignedIdEntity {   // shared/persistence: @Id, isNew flag, identity equals

    @Column(name = "user_id", nullable = false, updatable = false)
    private UUID userId;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "category_id")
    private Category category;

    @Column(nullable = false, precision = 12, scale = 2)
    private BigDecimal amount;

    @Column(nullable = false, length = 120)
    private String description;

    @Column(name = "expense_date", nullable = false)
    private LocalDate date;

    @Column(name = "created_at", nullable = false, updatable = false)
    private Instant createdAt;

    @Column(name = "updated_at", nullable = false)
    private Instant updatedAt;

    private Expense(UUID id) {
        super(id);
    }

    public static Expense create(UUID userId, Category category, BigDecimal amount,
                                 String description, LocalDate date, Instant now) {
        var expense = new Expense(UUID.randomUUID());
        expense.userId = userId;
        expense.createdAt = now;
        expense.apply(category, amount, description, date, now);
        return expense;
    }

    /** Full replacement (PUT). Intention-revealing instead of setters. */
    public void update(Category category, BigDecimal amount, String description,
                       LocalDate date, Instant now) {
        apply(category, amount, description, date, now);
    }

    private void apply(Category category, BigDecimal amount, String description,
                       LocalDate date, Instant now) {
        this.category = category;
        this.amount = amount.setScale(2, RoundingMode.UNNECESSARY); // validated before
        this.description = description.strip();
        this.date = date;
        this.updatedAt = now;
    }
}
```

No `@Data`, `@Setter` or `@EqualsAndHashCode`: they break with Hibernate proxies and let any
layer change state silently.

Every entity extends `shared/persistence/AssignedIdEntity` (see `User`, `RefreshToken`,
`RefreshTokenFamily`). The id is assigned in the factory, so Spring Data cannot use "id is null"
to decide persist vs merge; the base class answers `Persistable.isNew()` with a transient flag
flipped by `@PostPersist`/`@PostLoad`. Without it, every `save()` of a new entity runs an extra
`SELECT` and returns a copy instead of the same instance.

## 3. Repository

```java
public interface ExpenseRepository extends JpaRepository<Expense, UUID> {

    // Ownership is part of the query: another user's id simply is not found -> 404.
    Optional<Expense> findByIdAndUserId(UUID id, UUID userId);

    @Query("""
           select e from Expense e
           join fetch e.category
           where e.userId = :userId
             and e.date >= :from and e.date < :to
           order by e.date desc, e.createdAt desc
           """)
    List<Expense> findMonth(UUID userId, LocalDate from, LocalDate to); // fetch join: no N+1

    boolean existsByCategoryId(UUID categoryId);
}
```

Never take `userId` from anything except the service parameter that came from the token.

## 4. Service

```java
@Service
@RequiredArgsConstructor           // constructor injection; fields are final
public class ExpenseService {

    private final ExpenseRepository expenses;
    private final CategoryService categories;   // another feature: its Service, never its Repository
    private final ExpenseMapper mapper;
    private final Clock clock;

    @Transactional(readOnly = true)
    public List<ExpenseResponse> listMonth(UUID userId, YearMonth month) {
        return expenses.findMonth(userId, month.atDay(1), month.plusMonths(1).atDay(1))
                .stream().map(mapper::toResponse).toList();
    }

    @Transactional
    public ExpenseResponse create(UUID userId, ExpenseRequest request) {
        var category = categories.requireVisible(userId, request.categoryId()); // 404 if not visible
        var expense = Expense.create(userId, category, request.amount(),
                request.description(), request.date(), clock.instant());
        return mapper.toResponse(expenses.save(expense));
    }

    @Transactional
    public void delete(UUID userId, UUID expenseId) {
        var expense = expenses.findByIdAndUserId(expenseId, userId)
                .orElseThrow(NotFoundException::new);
        expenses.delete(expense);
    }
}
```

- `clock.instant()` / `LocalDate.now(clock)`, never `Instant.now()`: tests stay deterministic.
- The service throws domain exceptions. It never knows about HTTP status codes or `ResponseEntity`.
- **Uniqueness: insert, flush, recognize the violated constraint by name.** Never "exists? then
  insert" (two requests both see "free"). `saveAndFlush` makes the `INSERT` fail inside the method,
  where it can still be translated (see `UserService.create`):

```java
try {
    categories.saveAndFlush(category);
} catch (DataIntegrityViolationException e) {
    if (ConstraintViolations.violates(e, "uk_categories_user_name")) {   // exact name, never the message
        throw new CategoryNameTakenException();                           // no cause: nothing from the driver
    }
    throw e;                                                              // anything else: masked 500
}
```

- `@Transactional` is the default. A `TransactionTemplate` (built in the constructor from the
  injected `PlatformTransactionManager`) only when slow non-database work must run **before** the
  transaction opens, e.g. bcrypt in `AuthService.register` (ADR 0009).
- A lock wait past `lock_timeout` (3 s) is `CannotAcquireLockException`: never catch it and turn it
  into a `4xx`; it stays a masked `500`.

## 5. Controller

```java
@RestController
@RequestMapping("/api/v1/expenses")
@RequiredArgsConstructor
public class ExpenseController {

    private final ExpenseService service;

    @GetMapping
    public List<ExpenseResponse> list(@CurrentUserId UUID userId,
                                      @RequestParam YearMonth month) {   // bad format -> 400 via handler
        return service.listMonth(userId, month);
    }

    @PostMapping
    public ResponseEntity<ExpenseResponse> create(@CurrentUserId UUID userId,
                                                  @Valid @RequestBody ExpenseRequest request) {
        var created = service.create(userId, request);
        return ResponseEntity.created(URI.create("/api/v1/expenses/" + created.id())).body(created);
    }

    @DeleteMapping("/{id}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void delete(@CurrentUserId UUID userId, @PathVariable UUID id) {
        service.delete(userId, id);
    }
}
```

No `try/catch`, no repository, no entity. `@CurrentUserId` reads `sub` from the validated JWT
(see the `auth-flow` skill). There is no other way to obtain a user id.

## 6. DTOs (records)

```java
public record ExpenseRequest(
        @NotNull @DecimalMin(value = "0.01") @Digits(integer = 10, fraction = 2)
        @JsonFormat(shape = JsonFormat.Shape.STRING) BigDecimal amount,
        @NotBlank @Size(max = 120) String description,
        @NotNull LocalDate date,          // "max 1 day in the future" checked in the service with Clock
        @NotNull UUID categoryId) {}

public record ExpenseResponse(
        UUID id,
        @JsonFormat(shape = JsonFormat.Shape.STRING) BigDecimal amount,   // "42.90", never 42.9
        String description,
        LocalDate date,
        CategoryResponse category,
        Instant createdAt,
        Instant updatedAt) {}
```

A record holding a secret **must** mask `toString()`, because the default prints every field:

```java
// Login validates only "not blank + max 72 UTF-8 bytes": it must never reveal the password
// policy (8+ bytes is checked on register only). Both constraints live in shared/validation/.
public record LoginRequest(@NotNull @ValidEmail String email,
                           @NotBlank @Utf8ByteSize(max = 72) String password) {
    @Override
    public String toString() {
        return "LoginRequest[email=****, password=****]";   // email is personal data too
    }
}
```

Reusable constraints in `shared/validation/` (each has a fixed message that never echoes the value):

| Constraint | Use it for |
|---|---|
| `@Utf8ByteSize(min, max)` | Passwords (bcrypt reads at most 72 **bytes**); also rejects unpaired surrogates |
| `@CodePointLength(min, max)` | Display text limits in the contract's "chars" (an emoji is 1; matches `varchar(n)`). Never `@Size` for user text: it counts UTF-16 units |
| `@NoControlCharacters` | Display text (names): rejects Cc, Cf and unpaired surrogates |
| `@ValidEmail` | The contract's email format (ASCII, no whitespace, max 254), one violation |
| `@ValidCurrency` | ISO 4217 money codes (excludes metals, test, units of account, funds) |

## 7. Mapper

```java
@Mapper(componentModel = "spring", uses = CategoryMapper.class)
public interface ExpenseMapper {
    ExpenseResponse toResponse(Expense expense);
}
```

Never write `ExpenseMapperImpl` by hand. Requests are not mapped to entities by MapStruct:
entities are built through their factory methods (`Expense.create`), which hold invariants.

## 8. Errors

```java
// shared/error/ApiException.java
public abstract class ApiException extends RuntimeException {
    private final HttpStatus status;
    private final String slug;            // must exist in docs/api-contract.md "Errors"

    protected ApiException(HttpStatus status, String slug, String detail) {
        super(detail);
        this.status = status;
        this.slug = slug;
    }
    public HttpStatus status() { return status; }
    public String slug() { return slug; }
}

public class NotFoundException extends ApiException {
    public NotFoundException() { super(HttpStatus.NOT_FOUND, "not-found", "Resource not found."); }
}
```

A new error case in a feature is **one small subclass** using a `Slugs` constant. The slug must
already exist in the contract's Errors table; `ApiException` checks it in its constructor
(`ProblemFactory.requireKnownSlug`), so an unknown slug fails in the first test that throws it:

```java
// shared/error/CategoryInUseException.java: every ApiException subclass lives in shared/error/
// (next to Slugs), like EmailAlreadyRegisteredException and InvalidCredentialsException
public class CategoryInUseException extends ApiException {
    public CategoryInUseException() {
        super(HttpStatus.CONFLICT, Slugs.CATEGORY_IN_USE, "The category still has expenses.");
    }
}
```

A brand-new slug needs three edits in the same change: the contract's Errors table, `Slugs`
and the title map in `ProblemFactory` (the 14-pair test in `ProblemFactoryTest` catches a miss).

The shared infrastructure **already exists**. Read it instead of re-implementing it:

| File | Responsibility |
|---|---|
| `shared/error/Slugs.java` | The contract's error slugs as constants. Main code never writes a slug literal |
| `shared/error/ProblemFactory.java` | The only place that builds a ProblemDetail: `type = urn:snapledger:problem:<slug>`, fixed title per slug, `instance` = path; `requireKnownSlug` |
| `shared/error/GlobalExceptionHandler.java` | Maps every exception to a ProblemDetail (extends `ResponseEntityExceptionHandler`) |
| `shared/error/InternalErrors.java` | The catch-all `500 internal-error` body and its log line (errorId; database errors masked; bounded, non-throwing traversal); the committed-failure line and the client-disconnect `DEBUG` line. Used by the handler, by `ProblemErrorController` and by `CommittedResponseFailureFilter` |
| `shared/error/CommittedResponseFailureFilter.java` | Logs (through `InternalErrors.logCommitted`) a failure that escapes a filter after the response is committed, where `/error` never logs it; always rethrows. `REQUEST` dispatch only (ADR 0007 point 6) |
| `shared/error/ProblemErrorController.java` | Owns `/error`: errors the container forwards (firewall `400`, exceptions escaping MVC) keep their real status in our format; `nosniff` + `no-store` (ADR 0007) |
| `shared/security/ProblemResponseWriter.java` | Writes ProblemDetails from the security filters (before MVC) |
| `shared/error/ConstraintViolations.java` | Public `violates(failure, "uk_...")`: did this failure violate exactly that constraint? Reads Hibernate's parsed name through `InternalErrors.constraintName` (bounded traversal), never the message; never throws. Services use it to turn one violation into a `409` |

Rules the handler follows; keep them when you change it:

- `ApiException` → its own status and slug. `handleApi` returns a `ResponseEntity<ProblemDetail>`
  and adds `WWW-Authenticate: Bearer` only for the `unauthorized` slug (`UnauthorizedException`, e.g.
  `/users/me` when the token's user is gone), like the security entry point; other `401`s
  (`invalid-credentials`, `invalid-refresh-token`) never get it, because they are final for the app.
- `@Valid @RequestBody`, parameter constraints (`handleHandlerMethodValidationException`) and
  service-level `ConstraintViolationException` → `400 validation-error` with
  `errors: [{field, message}]` (`InvalidField` record). **Never** the rejected value.
- Type mismatch (bad UUID, bad `YearMonth`) is an **override of `handleTypeMismatch`**. A separate
  `@ExceptionHandler(MethodArgumentTypeMismatchException.class)` is ambiguous with the base class
  and fails at startup.
- Framework errors go through `handleExceptionInternal`: `ProblemFactory.forFrameworkStatus`
  gives 400/401/403/404/405/406/415 our slugs and fixed details and any other non-5xx status
  `about:blank` + reason phrase (same rule as `/error`); Spring's headers (`Allow`, `Accept`) are
  kept; any 5xx becomes `internal-error`.
- `AccessDeniedException` / `AuthenticationException` are **rethrown**, so the security layer
  answers 403/401. The catch-all must never swallow them. Consequence: domain auth errors
  (invalid credentials, invalid refresh token) must be `ApiException` subclasses, **never**
  subclasses of Spring's `AuthenticationException`.
- Catch-all `500`: always `InternalErrors.problem(ex, path)`, never a hand-built body or log
  line. Fixed detail plus an `errorId` string; the exception is logged with the id (logger
  category `InternalErrors`). If the exception **or anything reachable from it** (causes and
  suppressed exceptions) is a `DataAccessException`, `SQLException`, Hibernate `JDBCException` or
  `PersistenceException`, log only id, class and constraint name: driver messages quote column
  values (`Key (email)=(...) already exists`), and they often arrive wrapped in other exception
  types. Other loggers are covered by `logServerErrorDetail=false` and `logback-spring.xml`
  (`api/CLAUDE.md` security rule 8).
- Response already committed (`handleUnexpected` and `handleExceptionInternal` check it first):
  the catch-all **rethrows the same instance** without logging, so `CommittedResponseFailureFilter`
  logs it once and Tomcat aborts the connection (no clean last chunk). `handleExceptionInternal`
  does **not** rethrow (Spring's `DefaultHandlerExceptionResolver` would resolve it with unmasked
  WARNs and end the response cleanly): `InternalErrors.logCommitted(ex)` and return `null`. In both
  cases nothing is glued to the half-sent body and the base class's unmasked "Response already
  committed" WARN is skipped (ADR 0007 point 6).
- Client disconnect (`InternalErrors.isClientDisconnect`: `ClientAbortException` or
  `AsyncRequestNotUsableException` by type along the **cause chain only**, never among suppressed
  exceptions, and no database error anywhere in the graph): one `DEBUG` line through
  `InternalErrors.logClientDisconnect`, status `500` if not yet committed, return `null`. Never
  classify by message (ADR 0007 point 7).
- `logback-spring.xml` pins `ExceptionHandlerExceptionResolver` to `INFO`: at `DEBUG` it logs
  every resolved exception's `toString` unmasked (`api/CLAUDE.md` security rule 8).
- An `ASYNC` endpoint (`DeferredResult`, `StreamingResponseBody`, SSE) does not exist yet. The
  first one must register `CommittedResponseFailureFilter` for `DispatcherType.ASYNC` with a
  `FilterRegistrationBean` and add a committed-failure test (ADR 0007 point 6).
- Details are fixed texts. Framework messages can echo input and change between versions.

## 9. Tests

**Service: plain Mockito, no Spring context**

```java
@ExtendWith(MockitoExtension.class)
class ExpenseServiceTest {

    @Mock ExpenseRepository expenses;
    @Mock CategoryService categories;
    @Mock ExpenseMapper mapper;
    Clock clock = Clock.fixed(Instant.parse("2026-11-10T12:00:00Z"), ZoneOffset.UTC);
    ExpenseService service;

    @BeforeEach
    void setUp() { service = new ExpenseService(expenses, categories, mapper, clock); }

    @Test
    void deleteThrowsNotFoundWhenExpenseBelongsToAnotherUser() {
        var me = UUID.randomUUID();
        var someoneElsesExpense = UUID.randomUUID();
        when(expenses.findByIdAndUserId(someoneElsesExpense, me)).thenReturn(Optional.empty());

        assertThatThrownBy(() -> service.delete(me, someoneElsesExpense))
                .isInstanceOf(NotFoundException.class);
        verify(expenses, never()).delete(any());
    }
}
```

**Controller: `@WebMvcTest`, service mocked, asserts the contract**

`@WebMvcTest` loads `@ControllerAdvice` (the handler) automatically, but not our security
`@Component`s, the `Clock` or a JWT secret. `support/ImportSecurityStack` imports the security
set (SecurityConfig, the ProblemDetail handlers, AuthPathNotFoundHandler, TestJwtSecret). The
clock is **not** in it on purpose: each test picks `ClockConfig` or its own fixed clock (both
define a bean named `clock`, so they cannot coexist):

```java
@WebMvcTest(ExpenseController.class)
@ImportSecurityStack
@Import(ClockConfig.class)        // or a fixed-clock @TestConfiguration
class ExpenseControllerTest {

    @Autowired MockMvc mvc;
    @MockitoBean ExpenseService service;

    @Test
    void listRejectsMalformedMonthWithProblemDetail() throws Exception {
        mvc.perform(get("/api/v1/expenses").param("month", "2026-13")
                        .with(jwt().jwt(j -> j.subject(UUID.randomUUID().toString()))))
           .andExpect(status().isBadRequest())
           .andExpect(content().contentType(MediaType.APPLICATION_PROBLEM_JSON))
           .andExpect(jsonPath("$.type").value("urn:snapledger:problem:validation-error"));
    }

    @Test
    void listRequiresAuthentication() throws Exception {
        mvc.perform(get("/api/v1/expenses").param("month", "2026-11"))
           .andExpect(status().isUnauthorized());
    }
}
```

`jwt()` (from `spring-security-test`) injects an already-authenticated principal, so it skips
the decoder's validators. Token validation itself (audience, required claims, skew) is
covered once in `SecurityConfigTest` with real signed tokens.

**Test-only endpoints ("probes")**: nest a controller in the test class, mark it
`@TestComponent` and register it with `@Import`. Without `@TestComponent` it leaks into
other contexts (a probe on a path a real controller also maps, such as `/api/v1/auth/logout`, would
clash with it and break those contexts at startup).

```java
@WebMvcTest
@ImportSecurityStack
@Import({ClockConfig.class, SomeTest.Probe.class})
class SomeTest {
    @TestComponent
    @RestController
    static class Probe {
        @GetMapping("/api/v1/probe") String probe(@CurrentUserId UUID userId) { return userId.toString(); }
    }
}
```

**No literal secrets in tests**: `support/TestJwtSecret` generates one random 64-byte secret per
JVM and registers it with a `DynamicPropertyRegistrar` bean. Import it; never write a secret.

**Repository: real PostgreSQL via Testcontainers (never H2, never a shared DB)**

Declared once and imported where needed. Spring caches test contexts, so every test class
that shares a context reuses the same container (instead of one container per class):

```java
// src/test/java/.../support/TestcontainersConfiguration.java
@TestConfiguration(proxyBeanMethods = false)
public class TestcontainersConfiguration {
    @Bean
    @ServiceConnection   // Spring points the datasource at this container (overrides .env values)
    PostgreSQLContainer postgres() {
        return new PostgreSQLContainer("postgres:17-alpine");
    }
}
```

```java
@DataJpaTest
@Import(TestcontainersConfiguration.class)
@AutoConfigureTestDatabase(replace = AutoConfigureTestDatabase.Replace.NONE)
class ExpenseRepositoryTest {

    @Autowired ExpenseRepository expenses;

    @Test
    void findByIdAndUserIdDoesNotReturnAnotherUsersExpense() { /* arrange 2 users, assert empty */ }
}
```

Flyway runs the real migrations in this container, so these tests also prove that the
migrations and `ddl-auto=validate` agree.

**A native insert proves a CHECK.** The application would never send a forbidden value, so a
test that goes through the entity proves nothing about the constraint. Bypass it and assert the
constraint **name** (see `UserRepositoryTest`, `RefreshTokenRepositoryTest`):

```java
var insert = entityManager.getEntityManager().createNativeQuery("""
        insert into users (id, name, email, password_hash, currency, created_at)
        values (?1, ?2, ?3, ?4, ?5, ?6)
        """) /* .setParameter(...) */;

assertThatThrownBy(insert::executeUpdate)
        .isInstanceOf(PersistenceException.class)
        .rootCause().hasMessageContaining("ck_users_currency_format");
```

Fixtures that must pass a format CHECK use real values: `support/TestPasswordHashes.BCRYPT` is a
real bcrypt hash (cost 4, random password per JVM).

**End-to-end: `@SpringBootTest` + `@AutoConfigureMockMvc`, never a real port.** Only
`ContainerErrorDispatchIntegrationTest` may use `RANDOM_PORT`/`DEFINED_PORT`: a second embedded
Tomcat in the same JVM is named `Tomcat-1` and escapes the `[Tomcat]` wrapper logger pin in
`logback-spring.xml` (ADR 0007). Hook rule A11 rejects a port anywhere else.

**Shared test helpers live in `support/`** (`LockWaits`, `TestTokenHashes`,
`TestConstraintViolations`, `TestPasswordHashes`, `RefreshTokenFixtures`...): test classes never
import each other.

**Concurrency tests use real transactions** (see `RefreshTokenFamilyRepositoryTest`):

- `@Transactional(propagation = Propagation.NOT_SUPPORTED)` on the test, so each
  `TransactionTemplate.execute` really commits; the shared `EntityManager` proxy (autowired) works
  from any thread inside a template.
- An explicit `Executors.newFixedThreadPool(2)`; the setup goes **inside** the `try`, and the
  `finally` calls `shutdownNow()` and deletes what the test created (delete the user: `on delete
  cascade` removes the rest).
- Coordinate with `CountDownLatch`es, never `sleep`. To know the other transaction is really
  blocked, poll PostgreSQL: `LockWaits.awaitOneBlockedTransaction` waits until
  `pg_stat_activity` shows `wait_event_type = 'Lock'`. Then release the holder.
- Prove the test bites: remove the lock (or the condition) once and watch it fail.
