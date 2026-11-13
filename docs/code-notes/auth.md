# Code notes: auth

The long explanations behind the `auth` feature (`api/src/main/java/com/yulehohenfeld/snapledger/auth/`)
and its tables (`V2__create_refresh_tokens.sql`). The code keeps one short line and links here.
The design decisions are in [ADR 0002](../decisions/0002-refresh-token-rotation.md) (refresh
token rotation and reuse detection) and
[ADR 0008](../decisions/0008-refresh-token-family-row-serializes-revocation.md) (the family row
serializes rotation and revocation); the behavior is in the contract's
[Auth section](../api-contract.md#auth).

**PT:** As explicações longas por trás da feature `auth` e das tabelas dela
(`V2__create_refresh_tokens.sql`). O código mantém uma linha curta e aponta para cá. As decisões
de design estão no [ADR 0002](../decisions/0002-refresh-token-rotation.md) (rotação de refresh
token e detecção de reuso) e no
[ADR 0008](../decisions/0008-refresh-token-family-row-serializes-revocation.md) (a linha da
família serializa rotação e revogação); o comportamento está na
[seção Auth](../api-contract.md#auth) do contrato.

## RefreshToken

One refresh token of a session (table `refresh_tokens`, V2; ADR 0002). It holds only the SHA-256
of the token. The owner and the revocation live on the `RefreshTokenFamily` (ADR 0008), so they
have one source of truth. `usedAt` changes only through the atomic update of
`RefreshTokenRepository` ([`markUsed`](#markused)), never through this object, so two requests
can never both consume the same token.

**PT:** Um refresh token de uma sessão (tabela `refresh_tokens`, V2; ADR 0002). Ele guarda só o
SHA-256 do token. O dono e a revogação ficam na `RefreshTokenFamily` (ADR 0008), então têm uma
única fonte de verdade. O `usedAt` muda só pelo update atômico do `RefreshTokenRepository`
([`markUsed`](#markused)), nunca por este objeto, então duas requisições nunca conseguem consumir
o mesmo token.

## RefreshTokenRepository

Refresh tokens (ADR 0002). Consuming a token is a conditional update that returns the number of
rows changed: the database decides atomically, so "read then save" races cannot happen.
Revocation is not here: it lives on the family ([`RefreshTokenFamilyRepository`](#refreshtokenfamilyrepository),
ADR 0008). `findByTokenHash` takes no `userId`: it is a credential lookup, and the caller does
not know the user yet.

**PT:** Refresh tokens (ADR 0002). Consumir um token é um update condicional que devolve quantas
linhas mudaram: o banco decide de forma atômica, então disputas do tipo "ler e depois salvar" não
acontecem. A revogação não fica aqui: ela fica na família
([`RefreshTokenFamilyRepository`](#refreshtokenfamilyrepository), ADR 0008). O `findByTokenHash`
não recebe `userId`: é uma busca de credencial, e quem chama ainda não conhece o usuário.

### markUsed

Consumes the token. It returns 1 for the only caller that wins, and 0 when the token was already
used (including by a concurrent request: PostgreSQL re-checks `used_at is null` after waiting
for the row lock), is expired at `now`, or its family is revoked. The rotation must check expiry
and the family itself **before** calling this, so that 0 can only mean reuse: an expired token
is not reuse and must not revoke the session.

The family check inside the query is defense in depth, not the protection against the
revocation race: on its own it reads the family as of the statement start. The protection is
[`RefreshTokenFamilyRepository.lockActive`](#lockactive), called first (ADR 0008).

`flushAutomatically` writes pending inserts before the update runs; `clearAutomatically` drops
entities loaded earlier, so nobody reads a stale `usedAt` afterwards.

**PT:** Consome o token. Devolve 1 para o único chamador que vence, e 0 quando o token já foi
usado (inclusive por uma requisição simultânea: o PostgreSQL reavalia `used_at is null` depois de
esperar o lock da linha), está vencido em `now`, ou a família dele está revogada. A rotação
precisa conferir a validade e a família **antes** de chamar isto, para que 0 só possa significar
reuso: um token vencido não é reuso e não pode revogar a sessão.

**PT:** A conferência da família dentro da query é defesa em profundidade, não a proteção contra
a disputa com a revogação: sozinha ela lê a família como estava no início do comando. A proteção
é o [`RefreshTokenFamilyRepository.lockActive`](#lockactive), chamado antes (ADR 0008).

**PT:** O `flushAutomatically` grava os inserts pendentes antes de o update rodar; o
`clearAutomatically` descarta entidades carregadas antes, para que ninguém leia depois um
`usedAt` desatualizado.

## RefreshTokenProperties

Refresh token settings (ADR 0002), bound from `app.security.refresh-token`. A missing, zero or
negative TTL stops the application at startup instead of issuing tokens that are born expired.
The record is registered by `@ConfigurationPropertiesScan`.

**PT:** Configurações do refresh token (ADR 0002), lidas de `app.security.refresh-token`. Um TTL
ausente, zero ou negativo impede a aplicação de subir, em vez de emitir tokens que já nascem
vencidos. O record é registrado pelo `@ConfigurationPropertiesScan`.

## RefreshTokenFamily

One session: every refresh token born from the same login (table `refresh_token_families`, V2;
ADR 0002 and ADR 0008). It owns the session's state: the owner and whether it was revoked. Its
row exists before any rotation starts, so it is the point where rotation and revocation
serialize: rotation locks it first, revocation updates it. `revokedAt` changes only through the
conditional update of `RefreshTokenFamilyRepository` ([`revoke`](#revoke)), never through this
object.

The owner is a plain `userId`, not a relation to `User`: the auth feature never loads a `User`
through this entity, and features stay decoupled.

**PT:** Uma sessão: todo refresh token nascido do mesmo login (tabela `refresh_token_families`,
V2; ADR 0002 e ADR 0008). Ela guarda o estado da sessão: o dono e se foi revogada. A linha dela
existe antes de qualquer rotação começar, então é o ponto onde rotação e revogação se serializam:
a rotação a trava primeiro, a revogação a atualiza. O `revokedAt` muda só pelo update condicional
do `RefreshTokenFamilyRepository` ([`revoke`](#revoke)), nunca por este objeto.

**PT:** O dono é um `userId` simples, não uma relação com `User`: a feature auth nunca carrega um
`User` por esta entidade, e as features ficam desacopladas.

## RefreshTokenFamilyRepository

Sessions (ADR 0008). The family row is the serialization point between rotation and revocation:
both take its row lock (`RefreshTokenFamilyRepositoryTest` fails if `lockActive` loses its
`@Lock`), so they never overlap, and a revocation always sees, and kills, the token a rotation
issued before it. Lock order is always family first, then tokens, so the two flows cannot
deadlock each other. Credential lookups by id take no `userId`: the caller does not know the
user yet, the token is the credential.

**PT:** Sessões (ADR 0008). A linha da família é o ponto de serialização entre rotação e
revogação: as duas pegam o lock dessa linha (o `RefreshTokenFamilyRepositoryTest` falha se o
`lockActive` perder o `@Lock`), então nunca se sobrepõem, e uma revogação sempre vê, e mata, o
token que uma rotação emitiu antes dela. A ordem dos locks é sempre família primeiro, depois
tokens, então os dois fluxos não conseguem travar um ao outro (deadlock). Buscas de credencial
por id não recebem `userId`: quem chama ainda não conhece o usuário, o token é a credencial.

### lockActive

Step 1 of a rotation: it locks the family row until the transaction ends, and returns it only if
it is not revoked. Hibernate 7 renders `PESSIMISTIC_WRITE` on PostgreSQL as
`SELECT ... FOR NO KEY UPDATE`: it conflicts with the revocation's `UPDATE` and with another
rotation's lock, but not with the foreign-key check of the token this rotation inserts. If a
revocation holds the row, this waits; PostgreSQL then re-checks `revoked_at is null` on the
committed row and returns empty. It must be called inside the rotation's transaction, before
[`markUsed`](#markused) and before the new token is inserted.

**PT:** Passo 1 de uma rotação: trava a linha da família até a transação terminar, e a devolve só
se ela não estiver revogada. O Hibernate 7 traduz `PESSIMISTIC_WRITE` no PostgreSQL como
`SELECT ... FOR NO KEY UPDATE`: ele conflita com o `UPDATE` da revogação e com o lock de outra
rotação, mas não com a verificação de chave estrangeira do token que esta rotação insere. Se uma
revogação segura a linha, isto espera; o PostgreSQL então reavalia `revoked_at is null` na linha
já commitada e devolve vazio. Precisa ser chamado dentro da transação da rotação, antes do
[`markUsed`](#markused) e antes de inserir o token novo.

### revoke

Ends the session (logout or reuse). It returns 1 for the call that revoked it, and 0 when it was
already revoked or does not exist; the first revocation time is kept. Every token of the family
stops working at once, including one inserted by a rotation that committed just before:
[`markUsed`](#markused) checks the family.

`flushAutomatically` writes pending inserts before the update runs; `clearAutomatically` drops
entities loaded earlier, so nobody reads a stale `revokedAt` afterwards.

**PT:** Encerra a sessão (logout ou reuso). Devolve 1 para a chamada que a revogou, e 0 quando
ela já estava revogada ou não existe; o horário da primeira revogação é mantido. Todo token da
família para de funcionar de uma vez, inclusive um inserido por uma rotação que fez commit logo
antes: o [`markUsed`](#markused) confere a família.

**PT:** O `flushAutomatically` grava os inserts pendentes antes de o update rodar; o
`clearAutomatically` descarta entidades carregadas antes, para que ninguém leia depois um
`revokedAt` desatualizado.

## AuthResponse

`{ "user": UserResponse, "tokens": TokenResponse }`, the body of register and login. Its default
`toString` is safe because both parts mask their own sensitive fields.

**PT:** `{ "user": UserResponse, "tokens": TokenResponse }`, o corpo do cadastro e do login. O
`toString` padrão dele é seguro porque as duas partes mascaram os próprios campos sensíveis.

## LoginRequest

Body of [`POST /auth/login`](../api-contract.md#post-authlogin--public). The password is only
"not blank, at most 72 UTF-8 bytes": login never reveals the password policy (8+ bytes is checked
on register only), and users keep logging in if the policy changes. The 72-byte cap only refuses
input bcrypt could not read.

**PT:** Corpo de [`POST /auth/login`](../api-contract.md#post-authlogin--public). A senha é só
"não vazia, no máximo 72 bytes UTF-8": o login nunca revela a política de senha (8+ bytes é
conferido só no cadastro), e os usuários continuam entrando se a política mudar. O teto de 72
bytes só recusa uma entrada que o bcrypt não conseguiria ler.

## RegisterRequest

Body of [`POST /auth/register`](../api-contract.md#post-authregister--public). The compact
constructor trims the name and applies the currency default. Jackson builds records through this
constructor and Bean Validation runs afterwards, so validation already sees the trimmed name, as
the contract requires ("removed before validation"), and so does any other code that builds the
record.

The name counts characters as code points (an emoji is 1), like its `varchar(80)` column. The
password is `@NotBlank` as on login: a password of only spaces would register but could never
log in.

**PT:** Corpo de [`POST /auth/register`](../api-contract.md#post-authregister--public). O
construtor compacto apara o nome e aplica o default da moeda. O Jackson cria records por este
construtor e o Bean Validation roda depois, então a validação já vê o nome aparado, como o
contrato exige ("removido antes da validação"), e o mesmo vale para qualquer outro código que
crie o record.

**PT:** O nome conta caracteres como code points (um emoji é 1), como a coluna `varchar(80)`
dele. A senha é `@NotBlank` como no login: uma senha só de espaços seria cadastrada mas nunca
conseguiria entrar.

## TokenResponse

The contract's [`TokenResponse`](../api-contract.md#tokenresponse-shared-by-register-login-and-refresh),
shared by register, login and refresh. Lifetimes are in seconds.

**PT:** O [`TokenResponse`](../api-contract.md#tokenresponse-shared-by-register-login-and-refresh)
do contrato, compartilhado por cadastro, login e refresh. As validades estão em segundos.

### bearer

Builds the response from the two tokens and their TTLs, so the type is always `"Bearer"` and the
lifetimes always come from the same properties that set the expiry.

**PT:** Monta a resposta a partir dos dois tokens e das suas validades, para que o tipo seja
sempre `"Bearer"` e as validades venham sempre das mesmas propriedades que definem a expiração.

## V2__create_refresh_tokens

Opaque refresh tokens with rotation and reuse detection (ADR 0002), grouped in families whose
row serializes rotation and revocation (ADR 0008). Only the SHA-256 of a token is stored; the
raw token exists only in the response that issues it.

**PT:** Refresh tokens opacos com rotação e detecção de reuso (ADR 0002), agrupados em famílias
cuja linha serializa rotação e revogação (ADR 0008). Só o SHA-256 de um token é gravado; o token
cru existe apenas na resposta que o emite.

### refresh_token_families

One row per session (login or register). It holds the session state, owner and revocation, in
one place that exists before any rotation starts: rotation locks it, revocation updates it.

**PT:** Uma linha por sessão (login ou cadastro). Ela guarda o estado da sessão, dono e
revogação, num lugar só que existe antes de qualquer rotação começar: a rotação a trava, a
revogação a atualiza.

### token_hash column

`varchar` + an exact CHECK (`ck_refresh_tokens_token_hash_hex`) instead of `char(64)`: `char(n)`
silently pads a short value with spaces, so a broken hash would be stored; this way it is
rejected.

**PT:** `varchar` + CHECK exato (`ck_refresh_tokens_token_hash_hex`) em vez de `char(64)`: o
`char(n)` completa um valor curto com espaços sem avisar, então um hash quebrado seria gravado;
assim ele é rejeitado.
