# Code notes: expense

The long explanations behind the `expense` feature (`api/src/main/java/com/yulehohenfeld/snapledger/expense/`),
its table (`V8__create_expenses.sql`) and the three validators it introduced in `shared/validation/`
(`@MoneyAmount`, `@ValidExpenseDate`, `@ValidMonth`). The code keeps one short line and links here.
Behavior is defined by the contract: [Expenses](../api-contract.md#expenses).

**PT:** As explicações longas por trás da feature `expense`, da tabela (`V8__create_expenses.sql`)
e dos três validators que ela trouxe para `shared/validation/` (`@MoneyAmount`,
`@ValidExpenseDate`, `@ValidMonth`). O código mantém uma linha curta e aponta para cá. O
comportamento é definido pelo contrato: [Expenses](../api-contract.md#expenses).

## V8__create_expenses

Money is `numeric(12,2)`: exact decimal, never a float. Every rule the application validates is
repeated as a `CHECK` (positive amount, trimmed description without control characters, date from
2000, `updated_at >= created_at`), and a native `INSERT` test proves each one. The rules are cheap
and stable, so the database is a second wall behind the application.

**PT:** Dinheiro é `numeric(12,2)`: decimal exato, nunca float. Toda regra que a aplicação valida é
repetida como `CHECK` (valor positivo, descrição aparada sem caracteres de controle, data a partir
de 2000, `updated_at >= created_at`), e um teste com `INSERT` nativo prova cada uma. As regras são
baratas e estáveis, então o banco é uma segunda barreira atrás da aplicação.

### fk_expenses_categories

`on delete no action`, written explicitly, not `RESTRICT`. Both refuse to delete a category that
still has expenses with the same error (SQLSTATE 23503) and the same constraint name, which is
what the service turns into `409 category-in-use`. The difference is **when** the check runs:
`RESTRICT` fires immediately, `NO ACTION` at the end of the statement. Deleting a user cascades
to that user's categories (`fk_categories_users`) and expenses (`fk_expenses_users`) in one
statement; with `NO ACTION` the check waits until the whole cascade is done, so it never sees a
half-deleted state (a category already gone while its expenses are still being removed). With
`RESTRICT` the outcome could depend on the order PostgreSQL fires the two cascades. A test deletes
a user that owns a category with an expense. `NO ACTION` can also be made `DEFERRABLE` later
without changing the model; `RESTRICT` cannot.

Race with a concurrent insert: inserting an expense takes a share lock on its category row, and
deleting the category needs an exclusive lock. If the insert commits first, the delete fails the
check (`409`). If the delete commits first, the insert fails the same constraint, and the service
turns that into `404` (the category no longer exists for this user). Never a `500`.

**PT:** `on delete no action`, escrito explicitamente, não `RESTRICT`. Os dois recusam apagar uma
categoria que ainda tem despesas com o mesmo erro (SQLSTATE 23503) e o mesmo nome de constraint, e
é isso que o service transforma em `409 category-in-use`. A diferença é **quando** a checagem
roda: o `RESTRICT` dispara na hora, o `NO ACTION` no fim do comando. Apagar um usuário apaga em
cascata as categorias (`fk_categories_users`) e as despesas (`fk_expenses_users`) dele num só
comando; com `NO ACTION` a checagem espera a cascata inteira terminar, então nunca vê um estado
pela metade (uma categoria já apagada enquanto as despesas ainda estão sendo removidas). Com
`RESTRICT` o resultado poderia depender da ordem em que o PostgreSQL dispara as duas cascatas. Um
teste apaga um usuário que tem uma categoria com uma despesa. O `NO ACTION` também pode virar
`DEFERRABLE` depois sem mudar o modelo; o `RESTRICT` não.

Corrida com um insert concorrente: inserir uma despesa pega um lock compartilhado na linha da
categoria, e apagar a categoria precisa de um lock exclusivo. Se o insert confirma primeiro, o
delete falha na checagem (`409`). Se o delete confirma primeiro, o insert falha na mesma
constraint, e o service transforma isso em `404` (a categoria não existe mais para este usuário).
Nunca um `500`.

### ck_expenses_date_min

`expense_date >= 2000-01-01`. A typo such as year `0026` or `1926` is almost always a mistake, and
the oldest accepted month (`2000-01`) is the same bound the month filter uses. The upper bound
("tomorrow") depends on the clock, so only the application checks it (`@ValidExpenseDate`).

**PT:** `expense_date >= 2000-01-01`. Um erro de digitação como o ano `0026` ou `1926` é quase
sempre engano, e o mês mais antigo aceito (`2000-01`) é o mesmo limite do filtro de mês. O limite
superior ("amanhã") depende do relógio, então só a aplicação o confere (`@ValidExpenseDate`).

### idx_expenses_user_date

`(user_id, expense_date desc, created_at desc)` serves the month list for one user in display
order, and, being led by `user_id`, the foreign key on `user_id` too. `idx_expenses_category` serves
`fk_expenses_categories` (the "in use" check and the `?categoryId=` filter).

**PT:** `(user_id, expense_date desc, created_at desc)` atende a lista do mês de um usuário na
ordem de exibição e, por começar com `user_id`, também a chave estrangeira de `user_id`. O
`idx_expenses_category` atende a `fk_expenses_categories` (a checagem "em uso" e o filtro
`?categoryId=`).

## Expense

An expense of one user, with a lazy `@ManyToOne Category`. `create` and `update` both go through
`apply`, so the invariants (scale-2 amount, trimmed description) are written once. The amount is
`setScale(2, UNNECESSARY)`: the validator already guaranteed at most 2 decimals, so a value that
would need rounding throws instead of being silently rounded. `toString` prints the id only
(amount and description are personal financial data).

**PT:** Uma despesa de um usuário, com um `@ManyToOne Category` lazy. `create` e `update` passam
pelo `apply`, então as invariantes (valor com escala 2, descrição aparada) são escritas uma vez. O
valor usa `setScale(2, UNNECESSARY)`: o validator já garantiu no máximo 2 decimais, então um valor
que precisasse de arredondamento lança exceção em vez de ser arredondado em silêncio. O `toString`
imprime só o id (valor e descrição são dados financeiros pessoais).

### update

`update` replaces every editable field (PUT). `updated_at` is the clock instant but never earlier
than `created_at`: if the clock of another API instance is slightly behind, the row would break
`ck_expenses_updated_after_created` and the user would get a `500` for a harmless skew. Instants are
truncated to microseconds, what PostgreSQL stores.

**PT:** O `update` substitui todos os campos editáveis (PUT). O `updated_at` é o instante do
relógio, mas nunca anterior ao `created_at`: se o relógio de outra instância da API estiver um
pouco atrasado, a linha quebraria o `ck_expenses_updated_after_created` e o usuário receberia um
`500` por uma diferença inofensiva. Os instantes são truncados para microssegundos, o que o
PostgreSQL grava.

## ExpenseRepository

Every method takes `userId` and puts it in the `where`: ownership is proven by the query. The reads
`join fetch` the category, so building the response never triggers lazy loading (one query per
list, not one per row). `findMonth` takes the first and the last day of the month, both inclusive;
a `date` column has no time part, so `<= lastDay` has no end-of-day trap. The order is
`expense_date desc, created_at desc, id desc`: the id makes it total, so two requests never swap
rows with equal timestamps. `deleteByIdAndUserId` is one atomic statement; 0 rows means "not found
or not yours" (`404`), with no read-then-delete window.

**PT:** Todo método recebe `userId` e o coloca no `where`: a posse é provada pela consulta. As
leituras fazem `join fetch` da categoria, então montar a resposta nunca dispara carga lazy (uma
consulta por lista, não uma por linha). O `findMonth` recebe o primeiro e o último dia do mês,
ambos inclusivos; uma coluna `date` não tem hora, então `<= último dia` não tem a armadilha do fim
do dia. A ordem é `expense_date desc, created_at desc, id desc`: o id a torna total, então duas
requisições nunca trocam linhas com timestamps iguais. O `deleteByIdAndUserId` é um comando
atômico; 0 linhas significa "não existe ou não é seu" (`404`), sem janela de ler-e-depois-apagar.

### summary query

`sumByCategory` and `sumBetween` filter `expense_date >= :from and expense_date < :to` with `to`
the first day of the **next** month (half-open, ADR 0015): no function on the column, so
`idx_expenses_user_date` is used, and no month-length arithmetic. `sum` runs in PostgreSQL on
`numeric`, so `0.10 + 0.20` is exactly `0.30`. The category name comes from the join (defaults and
the user's own alike). `coalesce(sum, 0)` makes an empty month `0`, not `null`. Ownership is still
in the `where` (`e.userId = :userId`).

**PT:** `sumByCategory` e `sumBetween` filtram `expense_date >= :from and expense_date < :to`, com
`to` o primeiro dia do mês **seguinte** (semiaberto, ADR 0015): sem função na coluna, então o
`idx_expenses_user_date` é usado, e sem conta do tamanho do mês. O `sum` roda no PostgreSQL em
`numeric`, então `0.10 + 0.20` dá exatamente `0.30`. O nome da categoria vem do join (padrão e
próprias). O `coalesce(sum, 0)` faz o mês vazio ser `0`, não `null`. A posse continua no `where`.

## ExpenseSummaryService

One `@Transactional(readOnly = true)` method: the month rows, the previous month sum and the
user's currency (through `UserService`, never another repository). It is not one snapshot: under
PostgreSQL's default READ COMMITTED each statement sees its own, which is harmless here because
the two queries cover different months. The month total is the sum of the exact per-category
sums. The percentage is `part * 100 / total` in `BigDecimal`, scale 2, `HALF_UP`, and `0.00` when
the total is zero (no division; defensive only, since every amount is above zero). Order: total
desc, name case-insensitive (like the category list), then the id text, so equal rows never swap
between requests.
The previous month of January is December of the year before (`YearMonth.minusMonths`).

**PT:** Um método `@Transactional(readOnly = true)`: as linhas do mês, a soma do mês anterior e a
moeda do usuário (via `UserService`, nunca outro repository). Não é um snapshot único: no READ
COMMITTED padrão do PostgreSQL cada comando vê o seu, o que é inofensivo aqui porque as duas
queries cobrem meses diferentes. O total do mês é a soma das somas exatas por categoria. O
percentual é `parte * 100 / total` em `BigDecimal`, escala 2, `HALF_UP`, e `0.00` quando o total é
zero (sem divisão; só defensivo, pois todo valor é maior que zero). Ordem: total desc, nome sem
diferenciar maiúsculas (como a lista de categorias), depois o texto do id, então linhas iguais
nunca trocam entre requisições. O mês anterior de janeiro é
dezembro do ano anterior (`YearMonth.minusMonths`).

## ExpenseSummaryResponse

Same approach as `ExpenseResponse.amount`: `@JsonFormat(shape = STRING)` on every `BigDecimal`, and
the service sets scale 2, so `0` is written `"0.00"`. `toString()` carries the month only.

**PT:** Mesma abordagem do `ExpenseResponse.amount`: `@JsonFormat(shape = STRING)` em todo
`BigDecimal`, e o service fixa escala 2, então `0` sai `"0.00"`. O `toString()` leva só o mês.

## ExpenseService

Methods take `(UUID userId, record)` and return records, so the Phase 3b AI tools can call the same
service as the controller. Every category id that arrives (body or `?categoryId=`) goes through
`CategoryService.requireVisible`, so another user's category is the same `404` as one that does
not exist (security rule 13).

**PT:** Os métodos recebem `(UUID userId, record)` e devolvem records, então as tools de IA da
Fase 3b podem chamar o mesmo service do controller. Todo id de categoria que chega (corpo ou
`?categoryId=`) passa pelo `CategoryService.requireVisible`, então a categoria de outro usuário é
o mesmo `404` de uma que não existe (regra de segurança 13).

### create

`saveAndFlush` inside a `try`: between `requireVisible` and the insert the category may be deleted
by another request. The foreign key then rejects the insert with `fk_expenses_categories`, and the
service answers `404`, the same answer as if the category had never been visible. Any other
integrity violation is rethrown (masked `500`). `replace` does the same with `flush`.

**PT:** `saveAndFlush` dentro de um `try`: entre o `requireVisible` e o insert, a categoria pode
ser apagada por outra requisição. A chave estrangeira recusa o insert com `fk_expenses_categories`,
e o service responde `404`, a mesma resposta de se a categoria nunca tivesse sido visível. Qualquer
outra violação de integridade é relançada (`500` mascarado). O `replace` faz o mesmo com `flush`.

## ExpenseController

`/{id}` is typed as `UUID`, and `GET /expenses/summary` is a literal path: Spring prefers the
literal over the variable, so `summary` is never read as an id (a test proves the route). `month` is a `YearMonth` request parameter validated by `@ValidMonth`; a missing or
unparsable month is `400` from the framework handlers, which name the parameter and never echo its
value.

**PT:** O `/{id}` é tipado como `UUID`, e o `GET /expenses/summary` é um caminho literal: o
Spring prefere o literal à variável, então `summary` nunca é lido como id (um teste prova a rota). O `month` é um parâmetro `YearMonth` validado pelo
`@ValidMonth`; um mês ausente ou impossível de converter é `400` dos handlers do framework, que
citam o parâmetro e nunca repetem o valor.

## ExpenseRequest

`amount` is a `String`, validated by `@MoneyAmount`, and converted by `amountValue()` only after
validation. Why not `BigDecimal`: Jackson would parse `12.345` into a number and the application
would have to decide how to round; with text the exact characters the client sent are checked, so
nothing is ever rounded or lost (`1e3`, ` 12`, `12,50` are all visible as invalid). A JSON number
(`12.5`) still works because Jackson turns a number token into its original text (`"12.5"`), which
then has to match the same pattern; `1e3` becomes `"1e3"` and is rejected. The description is
stripped before validation, like the category name. `toString` masks amount and description.

**PT:** O `amount` é uma `String`, validada pelo `@MoneyAmount`, e convertida pelo `amountValue()`
só depois da validação. Por que não `BigDecimal`: o Jackson converteria `12.345` num número e a
aplicação teria de decidir como arredondar; com texto, os caracteres exatos que o cliente enviou
são conferidos, então nada é arredondado ou perdido (`1e3`, ` 12`, `12,50` aparecem todos como
inválidos). Um número JSON (`12.5`) ainda funciona porque o Jackson transforma o token numérico no
texto original (`"12.5"`), que então precisa casar com o mesmo padrão; `1e3` vira `"1e3"` e é
rejeitado. A descrição é aparada antes da validação, como o nome da categoria. O `toString`
mascara valor e descrição.

## ExpenseResponse

`amount` is a `BigDecimal` serialized as a string through `@JsonFormat(shape = STRING)`. The value
comes from `numeric(12,2)`, so it always has scale 2 and prints `"12.50"`, never `12.5` or `1.2E+1`.

**PT:** O `amount` é um `BigDecimal` serializado como string por `@JsonFormat(shape = STRING)`. O
valor vem de `numeric(12,2)`, então sempre tem escala 2 e imprime `"12.50"`, nunca `12.5` nem
`1.2E+1`.

## ExpenseMapper

Uses `CategoryMapper` (constructor injection) for the embedded category and maps `expenseDate` to
the contract's `date`.

**PT:** Usa o `CategoryMapper` (injeção por construtor) para a categoria embutida e mapeia
`expenseDate` para o `date` do contrato.

## MoneyAmount

The pattern `(0|[1-9][0-9]{0,9})(\.[0-9]{1,2})?` is matched against the **whole** text
(`matches()`, not `find()`, and no `$`, which in Java also accepts a trailing newline). `[0-9]` is
ASCII only, so Arabic-Indic or full-width digits are rejected. "Greater than zero" cannot be said
by a pattern, so the validator also requires at least one digit from 1 to 9. Max
`9999999999.99` follows from 10 integer digits and 2 decimals. The message never contains the
value.

**PT:** O padrão `(0|[1-9][0-9]{0,9})(\.[0-9]{1,2})?` é comparado com o texto **inteiro**
(`matches()`, não `find()`, e sem `$`, que em Java também aceita uma quebra de linha no fim). O
`[0-9]` é só ASCII, então dígitos árabe-índicos ou de largura total são rejeitados. "Maior que
zero" não dá para dizer com padrão, então o validator também exige ao menos um dígito de 1 a 9. O
máximo `9999999999.99` vem de 10 dígitos inteiros e 2 decimais. A mensagem nunca contém o valor.

## ValidExpenseDate

From `2000-01-01` (same as `ck_expenses_date_min`) up to **tomorrow in UTC**: a phone in a timezone
ahead of UTC can already be on the next calendar day. The validator receives the application
`Clock` by constructor injection (Spring builds validators with `SpringConstraintValidatorFactory`),
so tests fix "today". It reads the clock in UTC whatever zone the clock carries.

**PT:** De `2000-01-01` (igual ao `ck_expenses_date_min`) até **amanhã em UTC**: um celular num
fuso à frente do UTC já pode estar no dia seguinte. O validator recebe o `Clock` da aplicação por
injeção no construtor (o Spring cria validators com o `SpringConstraintValidatorFactory`), então os
testes fixam o "hoje". Ele lê o relógio em UTC seja qual for o fuso que o relógio carregue.

## ValidMonth

`2000-01` to `9999-12`. The lower bound matches the oldest expense date. The upper bound keeps the
year at four digits, so `YearMonth.atEndOfMonth()` and the text form always stay in the contract's
`YYYY-MM` shape (`YearMonth` itself accepts years up to 999999999).

**PT:** De `2000-01` a `9999-12`. O limite inferior combina com a data de despesa mais antiga. O
superior mantém o ano com quatro dígitos, então o `YearMonth.atEndOfMonth()` e a forma em texto
sempre ficam no formato `YYYY-MM` do contrato (o próprio `YearMonth` aceita anos até 999999999).
