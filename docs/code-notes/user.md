# Code notes: user

The long explanations behind the `user` feature (`api/src/main/java/com/yulehohenfeld/snapledger/user/`)
and its table (`V1__create_users.sql`). The code keeps one short line and links here. Behavior
is defined by the contract: [`UserResponse`](../api-contract.md#userresponse) and
[`POST /auth/register`](../api-contract.md#post-authregister--public).

**PT:** As explicações longas por trás da feature `user` e da tabela dela (`V1__create_users.sql`).
O código mantém uma linha curta e aponta para cá. O comportamento é definido pelo contrato:
[`UserResponse`](../api-contract.md#userresponse) e
[`POST /auth/register`](../api-contract.md#post-authregister--public).

## User

An account (table `users`, V1). It is built only through `register`, which holds the invariants
the database also checks: trimmed name, lowercase email. The id, `isNew` and identity-based
`equals` come from `AssignedIdEntity` (`shared/persistence/`).

**PT:** Uma conta (tabela `users`, V1). Ela é criada só pelo `register`, que garante as
invariantes que o banco também confere: nome aparado, email em minúsculas. O id, o `isNew` e o
`equals` por identidade vêm do `AssignedIdEntity` (`shared/persistence/`).

### normalizeEmail

The stored form of an email. Register and login must use the same rule, or a user could register
with one spelling and fail to log in with another. `Locale.ROOT` avoids language rules (for
example the Turkish "I"); the email is already ASCII only.

**PT:** A forma gravada de um email. Cadastro e login precisam usar a mesma regra, senão um
usuário poderia se cadastrar com uma grafia e não conseguir entrar com outra. O `Locale.ROOT`
evita regras de idioma (por exemplo o "I" turco); o email já é só ASCII.

## UserController

`GET /users/me`. The user id comes only from the validated access token (`@CurrentUserId`, the
`sub` claim); there is no id in the path, query or body, so the token id **is** the ownership
check: a caller can only ever ask for itself. When the token is valid but the user no longer exists
(account deleted after the token was issued), [`getCurrent`](#getcurrent) throws
`UnauthorizedException`, answered `401 unauthorized` with `WWW-Authenticate: Bearer`, the same as an
invalid token (contract), so the app refreshes and, when that fails too, logs in again. Thin like
every controller: one service call, no `try/catch`.

**PT:** `GET /users/me`. O id do usuário vem só do token de acesso validado (`@CurrentUserId`, a
claim `sub`); não existe id no caminho, na query ou no corpo, então o id do token **é** a
verificação de dono: quem chama só consegue pedir a si mesmo. Quando o token é válido mas o usuário
não existe mais (conta apagada depois de o token ser emitido), o [`getCurrent`](#getcurrent) lança
`UnauthorizedException`, respondida com `401 unauthorized` e `WWW-Authenticate: Bearer`, igual a um
token inválido (contrato), então o app tenta o refresh e, se isso também falhar, faz login de novo.
Fino como todo controller: uma chamada ao Service, sem `try/catch`.

## UserService

The only door to accounts for other features (`AuthService` today). It never returns the `User`
entity: callers get a `UserResponse` or, for login only, a `UserCredentials`.

**PT:** A única porta para as contas para outras features (hoje o `AuthService`). Ele nunca devolve
a entidade `User`: quem chama recebe um `UserResponse` ou, só para o login, um `UserCredentials`.

### create

Builds the account through `User.register` and calls `saveAndFlush`, so the `INSERT` runs now,
inside the caller's transaction (register's), and a duplicate email fails here instead of at
commit, where nobody could translate it. A `DataIntegrityViolationException` whose constraint is
exactly `uk_users_email` (`ConstraintViolations.violates`, see
[security.md](security.md#constraintviolations)) becomes `EmailAlreadyRegisteredException`
(`409`); any other violation (a CHECK, another unique) means a bug or a schema problem and
propagates to the masked `500`. The new exception has no cause on purpose: nothing from the driver
travels with a domain error.

After a violation PostgreSQL aborts the transaction, and the repository proxy marks it
rollback-only, so the whole register rolls back; nothing else runs after the throw.

Takes plain values, not `RegisterRequest`: that record belongs to `auth/`, and `user/` must not
depend on the feature that calls it.

**PT:** Monta a conta pelo `User.register` e chama `saveAndFlush`, então o `INSERT` roda agora,
dentro da transação de quem chama (a do cadastro), e um email duplicado falha aqui em vez de no
commit, onde ninguém conseguiria traduzi-lo. Uma `DataIntegrityViolationException` cuja constraint
é exatamente `uk_users_email` vira `EmailAlreadyRegisteredException` (`409`); qualquer outra
violação (um CHECK, outra unique) significa bug ou problema de esquema e se propaga para o `500`
mascarado. A exceção nova não tem causa de propósito: nada do driver viaja com um erro do domínio.

**PT:** Depois de uma violação o PostgreSQL aborta a transação, e o proxy do repositório a marca
como rollback-only, então o cadastro inteiro é desfeito; nada mais roda depois do throw.

**PT:** Recebe valores simples, não o `RegisterRequest`: esse record pertence ao `auth/`, e o
`user/` não pode depender da feature que o chama.

### findCredentials

Normalizes the email itself (`User.normalizeEmail`), so register and login can never apply
different rules, and the caller never needs the entity. Read-only transaction; returns empty for
an unknown email (the caller must still run bcrypt, see
[auth.md](auth.md#login)).

**PT:** Normaliza o email sozinho (`User.normalizeEmail`), então cadastro e login nunca podem
aplicar regras diferentes, e quem chama nunca precisa da entidade. Transação somente leitura;
devolve vazio para um email desconhecido (quem chama ainda precisa rodar o bcrypt, veja
[auth.md](auth.md#login)).

### getCurrent

The id comes from the validated token (`@CurrentUserId`), so this lookup is the ownership check.
A missing user is `401 unauthorized`, not `404` (contract, `GET /users/me`): the credential no
longer identifies anyone, and `401 unauthorized` makes the app refresh and, when that fails too,
log in again.

**PT:** O id vem do token validado (`@CurrentUserId`), então esta busca é a verificação de dono. Um
usuário ausente é `401 unauthorized`, não `404` (contrato, `GET /users/me`): a credencial não
identifica mais ninguém, e o `401 unauthorized` faz o app tentar o refresh e, se isso também
falhar, fazer login de novo.

## UserCredentials

What login needs from an account: the public profile (for the response) and the password hash
(for bcrypt). A small record instead of the entity, so `auth/` never imports `User` and cannot
change it. It never crosses the HTTP boundary, and its `toString` masks the hash.

**PT:** O que o login precisa de uma conta: o perfil público (para a resposta) e o hash da senha
(para o bcrypt). Um record pequeno em vez da entidade, para que o `auth/` nunca importe `User` nem
consiga alterá-lo. Ele nunca atravessa a fronteira HTTP, e o `toString` dele mascara o hash.

## UserMapper

Maps `User` to `UserResponse`, generated at compile time (no reflection at runtime). The opposite
direction does not exist: entities are built through `User.register`, which holds the
invariants. `componentModel = "spring"` makes the generated class a bean that services receive
by constructor injection.

**PT:** Converte `User` em `UserResponse`, gerado em tempo de compilação (sem reflexão em tempo
de execução). A direção oposta não existe: entidades são criadas pelo `User.register`, que
garante as invariantes. `componentModel = "spring"` faz da classe gerada um bean que os Services
recebem por injeção no construtor.

## UserRepository

Accounts. Uniqueness of the email is enforced by the `uk_users_email` constraint, not by a
"does it exist?" query before the insert: two concurrent registrations could both see "no"
([`api/CLAUDE.md`, "Database and Flyway"](../../api/CLAUDE.md#database-and-flyway): uniqueness
is enforced by the constraint). `findByEmail` takes no `userId`: it is a credential lookup, and
the caller does not know the user yet.

**PT:** Contas. A unicidade do email é garantida pela constraint `uk_users_email`, e não por uma
consulta "já existe?" antes do insert: dois cadastros simultâneos poderiam ver "não" ao mesmo
tempo ([`api/CLAUDE.md`, "Database and Flyway"](../../api/CLAUDE.md#database-and-flyway): a
unicidade é garantida pela constraint). O `findByEmail` não recebe `userId`: é uma busca de
credencial, e quem chama ainda não conhece o usuário.

## UserResponse

The contract's [`UserResponse`](../api-contract.md#userresponse). It never carries the password
hash: this record has no field for it, and `UserMapperTest` checks that the JSON has exactly the
contract's fields. MapStruct's `unmappedTargetPolicy=ERROR` does **not** protect against a leak:
it only fails when a field **of this record** has no source, so it would happily fill a
`passwordHash` field added here by mistake.

**PT:** O [`UserResponse`](../api-contract.md#userresponse) do contrato. Ele nunca leva o hash da
senha: este record não tem campo para ele, e o `UserMapperTest` confere que o JSON tem exatamente
os campos do contrato. O `unmappedTargetPolicy=ERROR` do MapStruct **não** protege contra
vazamento: ele só falha quando um campo **deste record** não tem origem, então preencheria sem
reclamar um campo `passwordHash` adicionado aqui por engano.

## V1__create_users

Accounts ([contract](../api-contract.md): `POST /auth/register` and `UserResponse`).

The id is generated by the application (`User.register`), not by a column default: the entity
has its identity before it is saved, and the rule lives in one place.

The CHECKs repeat the request validation on purpose (defense in depth): a bug or a future code
path that skips Bean Validation still cannot store a value the contract forbids.

**PT:** Contas ([contrato](../api-contract.md): `POST /auth/register` e `UserResponse`).

**PT:** O id é gerado pela aplicação (`User.register`), e não por um default da coluna: a
entidade tem identidade antes de ser salva, e a regra fica em um lugar só.

**PT:** Os CHECKs repetem a validação da requisição de propósito (defesa em profundidade): um bug
ou um caminho futuro que pule o Bean Validation continua sem conseguir gravar um valor que o
contrato proíbe.

### name column

`varchar(n)` counts characters (code points) in a UTF8 database, not bytes: 80 emoji fit,
exactly like `@CodePointLength(max = 80)` on the request.

**PT:** O `varchar(n)` conta caracteres (code points) num banco UTF8, não bytes: 80 emojis
cabem, exatamente como o `@CodePointLength(max = 80)` da requisição.

### password_hash column

BCrypt output is 60 characters; 72 leaves room for the `{bcrypt}` prefix of Spring's
`DelegatingPasswordEncoder` (68 characters).

**PT:** A saída do BCrypt tem 60 caracteres; 72 deixa espaço para o prefixo `{bcrypt}` do
`DelegatingPasswordEncoder` do Spring (68 caracteres).

### uk_users_email

Emails are stored lowercase (`ck_users_email_lowercase`), so a plain unique constraint is
already case-insensitive, and `where email = ?` uses its index directly.

**PT:** Os emails são gravados em minúsculas (`ck_users_email_lowercase`), então uma unique
simples já é insensível a maiúsculas, e `where email = ?` usa o índice dela diretamente.

### ck_users_name_trimmed

The application trims the name; `btrim` removes only spaces, so this never rejects a name the
application already trimmed.

**PT:** A aplicação apara o nome; o `btrim` remove só espaços, então isto nunca rejeita um nome
que a aplicação já aparou.

### ck_users_name_no_control_chars

Unicode control characters (category Cc: U+0001-U+001F, U+007F-U+009F; PostgreSQL already
refuses U+0000 in text). It is a fixed range that never changes between Unicode versions. Format
characters (Cf) are checked by the application only: they are a scattered list that grows with
Unicode, and PostgreSQL regular expressions have no `\p{Cf}`.

**PT:** Caracteres de controle Unicode (categoria Cc: U+0001-U+001F, U+007F-U+009F; o PostgreSQL
já recusa U+0000 em texto). É uma faixa fixa que nunca muda entre versões do Unicode. Caracteres
de formatação (Cf) são conferidos só pela aplicação: são uma lista espalhada que cresce com o
Unicode, e as expressões regulares do PostgreSQL não têm `\p{Cf}`.

### ck_users_password_hash_bcrypt

Matches what Spring's `BCryptPasswordEncoder` produces (`$2a$`, `$2b$` or `$2y$`, a two-digit
cost, 22 characters of salt + 31 of hash), optionally with the `{bcrypt}` prefix of the
`DelegatingPasswordEncoder`. A plain-text or truncated value can never be stored as a hash.

**PT:** Aceita o que o `BCryptPasswordEncoder` do Spring produz (`$2a$`, `$2b$` ou `$2y$`, custo
de dois dígitos, 22 caracteres de salt + 31 de hash), opcionalmente com o prefixo `{bcrypt}` do
`DelegatingPasswordEncoder`. Um valor em texto puro ou truncado nunca pode ser gravado como hash.
