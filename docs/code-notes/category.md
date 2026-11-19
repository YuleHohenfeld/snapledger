# Code notes: category

The long explanations behind the `category` feature (`api/src/main/java/com/yulehohenfeld/snapledger/category/`),
its three domain exceptions in `shared/error/` and its table (`V6__create_categories.sql`, seed in
`V7__seed_default_categories.sql`). The code keeps one short line and links here. Behavior is
defined by the contract: [Categories](../api-contract.md#categories).

**PT:** As explicações longas por trás da feature `category`, das três exceções de domínio dela em
`shared/error/` e da tabela (`V6__create_categories.sql`, seed na `V7__seed_default_categories.sql`).
O código mantém uma linha curta e aponta para cá. O comportamento é definido pelo contrato:
[Categories](../api-contract.md#categories).

## V6__create_categories

One table for both kinds of category. A default has `user_id` null and belongs to nobody; an own
category has the owner's id. One table means the expense foreign key (`category_id`) is a single
column that points at either kind, and "defaults + own" is one query.

**PT:** Uma tabela para os dois tipos de categoria. Uma padrão tem `user_id` nulo e não pertence a
ninguém; uma própria tem o id do dono. Uma tabela só significa que a chave estrangeira da despesa
(`category_id`) é uma coluna única que aponta para qualquer um dos tipos, e "padrão + próprias" é
uma só consulta.

### user_id column

Null = default category. `on delete cascade` removes a user's own categories with the user (the
defaults have no user, so they are never touched). The column is `updatable = false` in the entity:
a category never changes owner.

**PT:** Nulo = categoria padrão. O `on delete cascade` apaga as categorias próprias junto com o
usuário (as padrão não têm usuário, então nunca são tocadas). A coluna é `updatable = false` na
entidade: uma categoria nunca troca de dono.

### key column

A stable, lowercase code (`groceries`) that only defaults have. The app translates a default by its
`key` (the app is English first, Portuguese later), so a rename of the English `name` in a future
migration never breaks a translation. Own categories have `key` null because their name is the
user's own text. The partial unique index `uk_categories_key` keeps keys unique. The column is
`varchar(30)` and `ck_categories_key_format` limits it to `[a-z][a-z0-9_]*`.

**PT:** Um código estável em minúsculas (`groceries`) que só as padrão têm. O app traduz uma padrão
pela `key` (o app é inglês primeiro, português depois), então renomear o `name` em inglês numa
migration futura nunca quebra uma tradução. As categorias próprias têm `key` nula porque o nome é
texto do próprio usuário. O índice único parcial `uk_categories_key` mantém as chaves únicas. A
coluna é `varchar(30)` e o `ck_categories_key_format` a limita a `[a-z][a-z0-9_]*`.

### ck_categories_key_only_default

`key is null or user_id is null`: an own category can never carry a key. It protects the app's
translation rule ("a key means a default") even if some future code path forgets it.

**PT:** `key is null or user_id is null`: uma categoria própria nunca pode ter chave. Isso protege a
regra de tradução do app ("chave significa padrão") mesmo que um caminho de código futuro esqueça.

### name-trimmed

The app strips all Unicode whitespace from a name, while the CHECK uses `btrim` (spaces only), so the CHECK is intentionally weaker: a safety net, not the rule. Do not "tighten" it to match the app.

**PT:** O app remove todo espaço Unicode do nome, enquanto o CHECK usa `btrim` (só espaços comuns); o CHECK é mais fraco de propósito: é rede de segurança, não a regra. Não o "aperte" para igualar o app.

### uk_categories_user_name

Unique `(user_id, lower(name))` for own categories (`where user_id is not null`), so "Pets" and
"pets" collide for one user and two users may both have "Pets". It is a partial **index**, not a
table constraint, because PostgreSQL constraints cannot contain `lower(...)`. The service finds the
violation by this exact name (`ConstraintViolations.violates`). Its leading column is `user_id`, so
it also serves the foreign key on `user_id` (the project rule "every foreign key has an index").
`lower()` follows the database collation; Java's `lower(c.name)` in JPQL is translated to the same
SQL function, so query and index agree.

**PT:** Único em `(user_id, lower(name))` para as categorias próprias (`where user_id is not null`),
então "Pets" e "pets" colidem para um usuário e dois usuários podem ter "Pets". É um **índice**
parcial, não uma constraint de tabela, porque constraints do PostgreSQL não aceitam `lower(...)`. O
service reconhece a violação por este nome exato (`ConstraintViolations.violates`). A primeira
coluna é `user_id`, então ele também atende a chave estrangeira de `user_id` (a regra do projeto
"toda chave estrangeira tem índice"). O `lower()` segue a collation do banco; o `lower(c.name)` do
JPQL vira a mesma função SQL, então consulta e índice concordam.

### uk_categories_default_name

Unique `lower(name)` among the defaults only (`where user_id is null`), so a bad future seed cannot
create two defaults with the same name.

**PT:** Único em `lower(name)` só entre as padrão (`where user_id is null`), para que um seed
futuro errado não crie duas padrão com o mesmo nome.

## V7__seed_default_categories

The eight defaults with fixed UUID literals and keys. Fixed ids make every environment (and the
tests, and the app's fixtures) agree; they are valid UUID v4 shapes. Never edited after commit: a
new default or a rename is a new migration. `created_at` is a fixed instant so the migration is
deterministic.

**PT:** As oito padrão com UUIDs fixos e chaves. Ids fixos fazem todo ambiente (e os testes, e as
fixtures do app) concordarem; têm o formato de UUID v4. Nunca editada depois do commit: uma padrão
nova ou um rename é uma migration nova. O `created_at` é um instante fixo para a migration ser
determinística.

## Category

An entity for both kinds. `createOwn` builds an own category (the only way to create one in code;
defaults come from the migration). `isDefault()` is `userId == null`. `rename` refuses a default
with `IllegalStateException`: the service answers `403` before it gets there, so the exception only
guards a programming error. `toString` prints the id only because the name is user text.
Timestamps are truncated to microseconds, what PostgreSQL stores, so the value returned right
after a save equals the value read back later.

**PT:** Uma entidade para os dois tipos. O `createOwn` cria uma categoria própria (a única forma de
criar uma no código; as padrão vêm da migration). O `isDefault()` é `userId == null`. O `rename`
recusa uma padrão com `IllegalStateException`: o service responde `403` antes, então a exceção só
protege contra erro de programação. O `toString` imprime só o id porque o nome é texto do usuário.
Os timestamps são truncados para microssegundos, o que o PostgreSQL grava, então o valor devolvido
logo após o save é igual ao lido depois.

## CategoryRepository

`findVisible` orders defaults first (`case when user_id is null then 0 else 1`), then `lower(name)`,
then `id` so the order is total. `findVisibleById(id, userId)` is the ownership check: the same
query returns a default, the user's own category, and nothing for another user's, so the caller
cannot tell "other user's" from "does not exist" (`404`). Name uniqueness is never an exists-query
(see `uniqueness` below).

**PT:** O `findVisible` ordena padrão primeiro (`case when user_id is null then 0 else 1`), depois
`lower(name)`, depois `id` para a ordem ser total. O `findVisibleById(id, userId)` é a checagem de
posse: a mesma consulta devolve uma padrão, uma categoria do usuário e nada para a de outro, então
quem chama não distingue "de outro" de "não existe" (`404`). A unicidade do nome nunca é uma
consulta exists (veja `uniqueness` abaixo).

### default-name-clash

`existsDefaultNamedIgnoreCase` is the one exists-query allowed. The rule "an own name cannot equal
a default name" has no database index to lean on (it spans two partitions of the table), so the
service checks it. This is safe from races because the defaults change **only by migration**: no
request can add a default between the check and the insert. The own-vs-own rule, which can race,
stays on the unique index. A future migration that adds a default whose name equals an existing
own category would leave that user with a duplicate; that migration must rename or merge such
categories first.

**PT:** O `existsDefaultNamedIgnoreCase` é a única consulta exists permitida. A regra "um nome
próprio não pode ser igual a um nome padrão" não tem índice do banco em que se apoiar (atravessa
duas partições da tabela), então o service confere. Isso é seguro contra corrida porque as padrão
mudam **só por migration**: nenhuma requisição adiciona uma padrão entre a checagem e o insert. A
regra próprio-contra-próprio, que pode competir, fica no índice único. Uma migration futura que
adicione uma padrão com nome igual ao de uma categoria própria deixaria esse usuário com um
duplicado; essa migration precisa renomear ou juntar essas categorias antes.

## CategoryService

The only door to categories for other features: `ExpenseService` calls `requireVisible`, never the
repository. Methods take `(UUID userId, record)` and return records, so the Phase 3b AI tools can
call them like the controller does. `requireVisible` returns the entity because `Expense` holds a
`@ManyToOne Category`; it never leaves the service layer.

**PT:** A única porta para categorias para as outras features: o `ExpenseService` chama o
`requireVisible`, nunca o repository. Os métodos recebem `(UUID userId, record)` e devolvem
records, então as tools de IA da Fase 3b podem chamá-los como o controller faz. O `requireVisible`
devolve a entidade porque a `Expense` guarda um `@ManyToOne Category`; ela nunca sai da camada de
service.

### uniqueness

Check-then-insert would let two concurrent requests both see "free". The service inserts with
`saveAndFlush` (so the violation surfaces inside the `try`, not at commit) and turns exactly
`uk_categories_user_name` into `409 category-name-taken`; any other integrity violation is
rethrown and becomes a masked `500`. The loser of a race waits on the unique index until the
winner commits, then fails: exactly one `201` and one `409`, tested in `CategoryIntegrationTest`.

**PT:** Checar-e-inserir deixaria duas requisições concorrentes verem "livre". O service insere com
`saveAndFlush` (para a violação aparecer dentro do `try`, não no commit) e transforma exatamente o
`uk_categories_user_name` em `409 category-name-taken`; qualquer outra violação de integridade é
relançada e vira um `500` mascarado. Quem perde a corrida espera no índice único até o vencedor
confirmar, e então falha: exatamente um `201` e um `409`, testado no `CategoryIntegrationTest`.

### delete

`delete` + `flush` inside the `try`: the foreign key `fk_expenses_categories` is checked at the end
of the statement, and the flush forces that statement now. A violation of exactly that constraint
means "the category still has expenses" (`409 category-in-use`). The same constraint also covers
the race with a concurrent expense insert: whichever transaction commits first wins (see
`fk_expenses_categories` in [`expense.md`](expense.md#fk_expenses_categories)).

**PT:** `delete` + `flush` dentro do `try`: a chave estrangeira `fk_expenses_categories` é
conferida no fim do comando, e o flush força esse comando agora. Uma violação exatamente dessa
constraint significa "a categoria ainda tem despesas" (`409 category-in-use`). A mesma constraint
cobre a corrida com o insert concorrente de uma despesa: a transação que confirmar primeiro vence
(veja `fk_expenses_categories` em [`expense.md`](expense.md#fk_expenses_categories)).

## CategoryController

Thin: reads the user from the token (`@CurrentUserId`), validates the body, calls one service
method. `POST` answers `201` with `Location: /api/v1/categories/{id}` (a relative URI, as the
contract says). A malformed id in the path is a `400` from the type conversion, before the service.

**PT:** Fino: lê o usuário do token (`@CurrentUserId`), valida o corpo, chama um método do service.
O `POST` responde `201` com `Location: /api/v1/categories/{id}` (uma URI relativa, como diz o
contrato). Um id malformado no caminho é um `400` da conversão de tipo, antes do service.

## CategoryRequest

The name is stripped in the compact constructor **before** validation: `"  Pets "` is valid and
becomes `Pets`; `"   "` becomes empty and fails `@NotBlank`. Length counts code points
(`@CodePointLength`), like `varchar(40)`, and `@NoControlCharacters` rejects control and invisible
characters (they fake empty or identical names). `toString` masks the name.

**PT:** O nome é aparado no construtor compacto **antes** da validação: `"  Pets "` é válido e
vira `Pets`; `"   "` vira vazio e falha no `@NotBlank`. O tamanho conta code points
(`@CodePointLength`), como o `varchar(40)`, e o `@NoControlCharacters` rejeita caracteres de
controle e invisíveis (eles forjam nomes vazios ou idênticos). O `toString` mascara o nome.

## CategoryResponse

`@JsonProperty("isDefault")` pins the JSON name: a record component called `isDefault` would
otherwise be read by Jackson as the boolean getter of a property named `default`. `key` is always
serialized (null for own categories), so the app never has to tell "absent" from "null".

**PT:** O `@JsonProperty("isDefault")` fixa o nome no JSON: um componente de record chamado
`isDefault` poderia ser lido pelo Jackson como o getter booleano de uma propriedade chamada
`default`. A `key` é sempre serializada (nula nas próprias), então o app nunca precisa distinguir
"ausente" de "nulo".

## CategoryMapper

The record component is `isDefault` but the entity method is `isDefault()` (property `default` for
MapStruct), so the mapping is written explicitly. With `unmappedTargetPolicy=ERROR` a new field in
the response without a mapping fails the build.

**PT:** O componente do record é `isDefault`, mas o método da entidade é `isDefault()` (propriedade
`default` para o MapStruct), então o mapeamento é escrito explicitamente. Com
`unmappedTargetPolicy=ERROR`, um campo novo na resposta sem mapeamento quebra o build.

## category-exceptions

`DefaultCategoryReadOnlyException` (`403`), `CategoryNameTakenException` (`409`) and
`CategoryInUseException` (`409`) only carry their contract slug and a fixed detail. The
name-taken detail names the field (`name`) and never quotes the value, so a log or a response
never repeats user text.

**PT:** `DefaultCategoryReadOnlyException` (`403`), `CategoryNameTakenException` (`409`) e
`CategoryInUseException` (`409`) só carregam o slug do contrato e um detalhe fixo. O detalhe do
nome repetido cita o campo (`name`) e nunca o valor, então um log ou uma resposta nunca repete
texto do usuário.
