---
name: spring-patterns
description: Minimal, correct examples of every layer of the SnapLedger API (Spring Boot 4, Java 21) - Flyway migration, JPA entity, Spring Data repository scoped by userId, service with @Transactional and Clock, thin controller with current-user resolver, record DTOs (money as string, masked toString), MapStruct mapper, ApiException + GlobalExceptionHandler with ProblemDetail, and tests (Mockito, @WebMvcTest, @DataJpaTest + Testcontainers). Load when writing, planning or reviewing any code under api/, or when deciding "which layer does this belong to?".
---

# SnapLedger API patterns

Rules live in `api/CLAUDE.md`; this skill shows **how** to follow them. Examples use the
`expense` feature and are deliberately minimal. When real code exists, **the code wins**:
follow the sibling feature and report any divergence from this skill so it gets updated.

Imports are omitted unless they are not obvious. Spring Boot 4 moved several test
annotations into new modules. If an import does not resolve, check the module/package for
the Boot version in `pom.xml` instead of changing the pattern.

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
public class Expense {

    @Id
    private UUID id;

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

    public static Expense create(UUID userId, Category category, BigDecimal amount,
                                 String description, LocalDate date, Instant now) {
        var expense = new Expense();
        expense.id = UUID.randomUUID();
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
public record LoginRequest(@NotBlank @Email String email,
                           @NotBlank @Size(min = 8, max = 72) String password) {
    @Override
    public String toString() {
        return "LoginRequest[email=" + email + ", password=****]";
    }
}
```

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

```java
// shared/error/GlobalExceptionHandler.java
@RestControllerAdvice
@Slf4j
public class GlobalExceptionHandler extends ResponseEntityExceptionHandler {

    static final String TYPE_PREFIX = "urn:snapledger:problem:";

    @ExceptionHandler(ApiException.class)
    ProblemDetail handleApi(ApiException ex) {
        return problem(ex.status(), ex.slug(), ex.getMessage());
    }

    @Override   // @Valid on @RequestBody
    protected ResponseEntity<Object> handleMethodArgumentNotValid(
            MethodArgumentNotValidException ex, HttpHeaders headers,
            HttpStatusCode status, WebRequest request) {
        var body = problem(HttpStatus.BAD_REQUEST, "validation-error", "One or more fields are invalid.");
        body.setProperty("errors", ex.getBindingResult().getFieldErrors().stream()
                .map(e -> Map.of("field", e.getField(), "message", e.getDefaultMessage()))
                .toList());                               // never e.getRejectedValue()
        return ResponseEntity.badRequest().body(body);
    }

    @ExceptionHandler(MethodArgumentTypeMismatchException.class)   // bad UUID, bad YearMonth
    ProblemDetail handleTypeMismatch(MethodArgumentTypeMismatchException ex) {
        return problem(HttpStatus.BAD_REQUEST, "validation-error",
                "Invalid value for parameter '" + ex.getName() + "'.");
    }

    @ExceptionHandler(Exception.class)
    ProblemDetail handleUnexpected(Exception ex) {
        var errorId = UUID.randomUUID();
        log.error("Unexpected error id={}", errorId, ex);  // detail stays in the log
        var body = problem(HttpStatus.INTERNAL_SERVER_ERROR, "internal-error", "Unexpected error.");
        body.setProperty("errorId", errorId);
        return body;
    }

    private static ProblemDetail problem(HttpStatus status, String slug, String detail) {
        var body = ProblemDetail.forStatusAndDetail(status, detail);
        body.setType(URI.create(TYPE_PREFIX + slug));
        return body;
    }
}
```

Extending `ResponseEntityExceptionHandler` makes framework errors (malformed JSON,
unsupported method, missing params) come out as ProblemDetail too. Override only what needs
a custom shape.

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

```java
@WebMvcTest(ExpenseController.class)
@Import({SecurityConfig.class, GlobalExceptionHandler.class})
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

**Repository: real PostgreSQL via Testcontainers (never H2, never a shared DB)**

```java
@DataJpaTest
@Testcontainers
@AutoConfigureTestDatabase(replace = AutoConfigureTestDatabase.Replace.NONE)
class ExpenseRepositoryTest {

    @Container
    @ServiceConnection
    static PostgreSQLContainer postgres = new PostgreSQLContainer("postgres:17-alpine");

    @Autowired ExpenseRepository expenses;

    @Test
    void findByIdAndUserIdDoesNotReturnAnotherUsersExpense() { /* arrange 2 users, assert empty */ }
}
```

Flyway runs the real migrations in this container, so these tests also prove that the
migrations and `ddl-auto=validate` agree.
