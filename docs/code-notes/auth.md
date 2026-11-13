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

## AuthService

Register, login, refresh and logout. It reaches accounts only through `UserService` (a feature calls another
feature's Service, never its Repository) and never sees the `User` entity: `UserService` returns a
`UserResponse` (register) or a `UserCredentials` (login), so `auth/` imports nothing from `user/`
except its Service and DTOs.

**PT:** Cadastro, login, refresh e logout. Ele chega às contas só pelo `UserService` (uma feature chama o Service de
outra, nunca o Repository dela) e nunca vê a entidade `User`: o `UserService` devolve um
`UserResponse` (cadastro) ou um `UserCredentials` (login), então o `auth/` não importa nada do
`user/` além do Service e dos DTOs.

### register

**Hash first, then one transaction** ([ADR 0009](../decisions/0009-password-hashing-and-database-lock-timeout.md)).
The method is **not** `@Transactional`: the annotation would open the transaction, and take a pool
connection, before bcrypt (tens of milliseconds) runs, so connections would sit idle while the CPU
hashes. Instead it calls `passwordEncoder.encode` with no transaction open, then runs
`UserService.create` (inserts and flushes at once), `RefreshTokenService.startFamily` and the
access token (no database) inside one `TransactionTemplate.execute`. Both `@Transactional` methods
join that transaction, so if anything fails after the user insert, everything rolls back and no
account is left behind (contract: "either the account is created *and* the session is started, or
nothing is created"). `AuthIntegrationTest` forces `startFamily` to fail and checks that no user
row exists, and checks that no transaction is active while the password is hashed;
`AuthServiceTest` checks the order hash → begin → create → session → commit.

The template is built in the constructor from the injected `PlatformTransactionManager` (the
pattern of Spring's reference documentation) instead of injecting Boot's shared
`TransactionTemplate` bean: a `TransactionTemplate` is mutable, so its settings belong to this
class, and the service depends on the transaction manager, not on an auto-configured helper.

Only the hash ever reaches the user feature and the database; the raw password never leaves this
method.

A taken email is detected by the unique constraint (`UserService.create`), not by a query before
the insert: two concurrent registers of the same email give exactly one `201` and one `409`
(`AuthIntegrationTest`).

**PT:** **Hash primeiro, depois uma transação** ([ADR 0009](../decisions/0009-password-hashing-and-database-lock-timeout.md)).
O método **não** é `@Transactional`: a anotação abriria a transação, e pegaria uma conexão do pool,
antes de o bcrypt (dezenas de milissegundos) rodar, então conexões ficariam paradas enquanto a CPU
calcula. Em vez disso ele chama `passwordEncoder.encode` sem transação aberta, e depois roda o
`UserService.create` (insere e faz flush na hora), o `RefreshTokenService.startFamily` e o token de
acesso (sem banco) dentro de um único `TransactionTemplate.execute`. Os dois métodos
`@Transactional` entram nessa transação, então se algo falha depois do insert do usuário, tudo é
desfeito e nenhuma conta fica para trás (contrato: "ou a conta é criada *e* a sessão iniciada, ou
nada é criado"). O `AuthIntegrationTest` força o `startFamily` a falhar e confere que não existe
linha de usuário, e confere que nenhuma transação está ativa enquanto a senha vira hash; o
`AuthServiceTest` confere a ordem hash → begin → create → sessão → commit.

**PT:** O template é criado no construtor a partir do `PlatformTransactionManager` injetado (o
padrão da documentação de referência do Spring) em vez de injetar o bean `TransactionTemplate`
compartilhado do Boot: um `TransactionTemplate` é mutável, então as configurações dele pertencem a
esta classe, e o Service depende do gerenciador de transações, não de um auxiliar autoconfigurado.

**PT:** Só o hash chega à feature user e ao banco; a senha crua nunca sai deste método.

**PT:** Um email já usado é detectado pela constraint unique (`UserService.create`), não por uma
consulta antes do insert: dois cadastros simultâneos do mesmo email dão exatamente um `201` e um
`409` (`AuthIntegrationTest`).

### login

**No outer transaction** (owner decision Q5): the lookup is its own read-only transaction, bcrypt
runs with no connection held, and only `startFamily` opens a write transaction. Login has nothing
to make atomic: if `startFamily` fails, nothing was written.

**No enumeration** (contract): an unknown email still runs `passwordEncoder.matches`, against a
dummy hash computed once at startup with the same encoder (so the same cost), and both cases throw
the same `InvalidCredentialsException`, same body. The check `account.isEmpty() || !matches` means
an unknown email can never log in, even if the dummy hash matched. The remaining timing difference
is one indexed lookup that finds nothing versus one that finds a row, which is far below network
noise; bcrypt dominates both paths.

**PT:** **Sem transação externa** (decisão do dono, Q5): a busca é a própria transação somente
leitura, o bcrypt roda sem segurar conexão, e só o `startFamily` abre uma transação de escrita. O
login não tem nada para tornar atômico: se o `startFamily` falha, nada foi gravado.

**PT:** **Sem enumeração** (contrato): um email desconhecido ainda roda o `passwordEncoder.matches`,
contra um hash falso calculado uma vez na inicialização com o mesmo encoder (então o mesmo custo),
e os dois casos lançam a mesma `InvalidCredentialsException`, com o mesmo corpo. A condição
`account.isEmpty() || !matches` garante que um email desconhecido nunca entra, mesmo se o hash
falso batesse. A diferença de tempo que sobra é uma busca indexada que não acha nada contra uma
que acha uma linha, muito abaixo do ruído da rede; o bcrypt domina os dois caminhos.

### refresh

`refreshTokens.rotate(...)`, then `accessTokens.issue(rotation.userId())`, then
`TokenResponse.bearer(...)` with both TTLs. **Never `@Transactional` and no `TransactionTemplate`**:
`rotate` joins an existing transaction, so an outer one would make `rotate`'s
`noRollbackFor` useless: the `InvalidRefreshTokenException` leaving `refresh` would roll the outer
transaction back, reuse revocation included (ADR 0008 amendment). `AuthServiceTest` checks that
neither `refresh` nor `logout` is annotated or touches the transaction manager.

Signing happens after `rotate` has committed (owner decision Q6). If signing ever failed there
(it is in-memory HMAC; practically only a bug), the old token is already used and the new one was
never delivered: the user has to log in again. Accepted: the alternative, signing inside the
transaction, needs exactly the outer transaction rejected above.

**PT:** `refreshTokens.rotate(...)`, depois `accessTokens.issue(rotation.userId())`, depois
`TokenResponse.bearer(...)` com as duas validades. **Nunca `@Transactional` e sem
`TransactionTemplate`**: o `rotate` entra numa transação existente, então uma transação externa
tornaria inútil o `noRollbackFor` do `rotate`: a `InvalidRefreshTokenException` saindo do `refresh`
desfaria a transação externa, inclusive a revogação por reuso (emenda do ADR 0008). O
`AuthServiceTest` confere que nem `refresh` nem `logout` são anotados ou mexem no gerenciador de
transações.

**PT:** A assinatura acontece depois de o `rotate` fazer commit (decisão do dono, Q6). Se a
assinatura falhasse ali (é um HMAC em memória; na prática só um bug), o token antigo já foi usado e o
novo nunca foi entregue: o usuário precisa entrar de novo. Aceito: a alternativa, assinar dentro da
transação, precisa justamente da transação externa descartada acima.

### logout

Delegates to [`revokeFamilyOf`](#revokefamilyof) and issues nothing. Not transactional, for the same
reason as `refresh` and because it has nothing to make atomic.

**PT:** Delega para o [`revokeFamilyOf`](#revokefamilyof) e não emite nada. Não é transacional, pelo
mesmo motivo do `refresh` e porque não tem nada para tornar atômico.

## AuthController

Thin: `@Valid`, one service call, no `try/catch`, no user id. Register answers `201` without
`Location` (the contract defines none: the created resource is read through `/users/me`). Refresh
answers `200` with a bare `TokenResponse` (contract: no `user`), logout `204` with no body
(`@ResponseStatus`, like a delete). The three responses with tokens carry
`Cache-Control: no-store` and `Pragma: no-cache`, as RFC 6749 §5.1 requires for responses with
tokens. Spring Security already adds `no-cache, no-store...` by default, but it skips the header
when the controller sets one, and writing it here keeps the guarantee even if the default header
writer is ever changed. `Pragma` is only for HTTP/1.0 caches; it costs nothing and matches the RFC.

**PT:** Fino: `@Valid`, uma chamada ao Service, sem `try/catch`, sem id de usuário. O cadastro
responde `201` sem `Location` (o contrato não define nenhum: o recurso criado é lido pelo
`/users/me`). O refresh responde `200` com um `TokenResponse` puro (contrato: sem `user`), o logout
`204` sem corpo (`@ResponseStatus`, como um delete). As três respostas com tokens levam
`Cache-Control: no-store` e `Pragma: no-cache`, como a RFC 6749 §5.1 exige para respostas com
tokens. O Spring Security já adiciona `no-cache, no-store...` por padrão, mas não
mexe no header quando o controller define um, e escrevê-lo aqui mantém a garantia mesmo se o
escritor de headers padrão um dia mudar. O `Pragma` é só para caches HTTP/1.0; não custa nada e
segue a RFC.

## AccessTokenService

Signs the access token with the `JwtEncoder` of `SecurityConfig` (same key as the decoder) and the
claims ADR 0006 requires: `iss`, `aud = JwtProperties.AUDIENCE`, `sub` = user id, `iat`, `exp`.
`now` comes from the injected `Clock`, the same one the decoder's timestamp validator uses, so
issuing and validating agree about time. No email or name in the token: it is only base64, anyone
holding it can read it. `AccessTokenServiceTest` decodes the issued token with the application's
own strict decoder and opens `/users/me` with it.

**PT:** Assina o token de acesso com o `JwtEncoder` do `SecurityConfig` (mesma chave do decoder) e
as claims que o ADR 0006 exige: `iss`, `aud = JwtProperties.AUDIENCE`, `sub` = id do usuário,
`iat`, `exp`. O `now` vem do `Clock` injetado, o mesmo que o validador de tempo do decoder usa,
então emitir e validar concordam sobre o tempo. Sem email nem nome no token: ele é só base64,
qualquer um que o tenha consegue lê-lo. O `AccessTokenServiceTest` decodifica o token emitido com
o decoder estrito da própria aplicação e abre o `/users/me` com ele.

## RefreshTokenService

Issues, rotates and revokes opaque refresh tokens (ADR 0002). Rotation and logout follow ADR 0008
and its amendment: `lockActive` first, `noRollbackFor` on reuse, family before tokens.

**PT:** Emite, rotaciona e revoga refresh tokens opacos (ADR 0002). Rotação e logout seguem o ADR
0008 e a emenda dele: `lockActive` primeiro, `noRollbackFor` no reuso, família antes dos tokens.

### rotate

The order is fixed (ADR 0008):

1. `findByTokenHash(sha256(raw))`. Not found → `InvalidRefreshTokenException`; nothing is locked.
2. `lockActive(familyId)`: `SELECT ... FOR NO KEY UPDATE` on the family row, only if not revoked.
   It waits for a concurrent rotation or revocation of the **same session**. Empty (revoked, or
   revoked while we waited) → the same exception, no revoke.
3. `now` is read from the `Clock` **after** the lock, truncated to microseconds. After the lock,
   so a rotation that waited judges expiry at the moment it runs. Microseconds, because PostgreSQL
   stores `timestamptz` with microseconds and pgjdbc **rounds** extra nanoseconds: without the
   truncation, a token expiring within the same microsecond could pass the Java check, fail
   `markUsed`'s `expires_at > now` and be treated as reuse, revoking a healthy session.
   Expired (`expiresAt <= now`, the same boundary `markUsed` uses) → the same exception, **no
   revoke and no `markUsed`**: expiry is not reuse.
4. `markUsed(id, now)`. Under the family lock, with expiry already checked, `0` can only mean
   "already used": **reuse**. The family is revoked, one `WARN` line is logged with only the family
   id (never the token, its hash, the user or an email; owner decision Q3), and the same exception
   is thrown.
5. Otherwise a new token is issued in the **same family** and `Rotation(family.userId, token)` is
   returned. The user comes from the locked family row, never from the request.

**`noRollbackFor = InvalidRefreshTokenException.class`**: by default a `RuntimeException` rolls the
transaction back, which would undo the revocation of step 4, and the attacker holding the newest
token would keep the session. With `noRollbackFor` the transaction commits and the exception still
reaches the client as `401`. The other failure paths wrote nothing, so committing them is harmless
(and releases the lock). `REQUIRES_NEW` for the revocation was rejected: the outer transaction holds
the family row lock, so the inner `UPDATE` would wait for its own caller until `lock_timeout`
(see the [ADR 0008 amendment](../decisions/0008-refresh-token-family-row-serializes-revocation.md#amendment-2026-11-13-reuse-revocation-must-commit)).

**`CannotAcquireLockException` is never caught.** A lock wait past `lock_timeout` (3 s, ADR 0009)
propagates as a masked `500`; the token is untouched (`used_at` still null), so the client can retry.
A `401` here would make the app wipe a healthy session because the database was slow.

**Response times differ, and that is accepted.** An unknown token answers after one indexed lookup,
a known one after the lock and the updates, a reused one after the revocation too; logout
([`revokeFamilyOf`](#revokefamilyof)) differs the same way. The bodies are identical, but the timing
can tell "this token exists" from "it does not". That is harmless: a refresh token has 256 random
bits, so nobody can guess one to probe with, and knowing that a token you already hold exists tells
you nothing new. Do **not** add artificial delays or dummy work to equalize them: they cost every
request and protect nothing. (Login is different: there the secret is a low-entropy password and
the email is guessable, so it does equalize with a dummy hash.)

`RefreshTokenServiceTest` checks the order with `InOrder`, the expiry boundary, the clock read after
the lock, the truncation with a nanosecond clock just before expiry, the WARN line and the
annotations. `RefreshTokenServiceIntegrationTest` proves it on a real
PostgreSQL with real commits: reuse revokes the family and the newest token fails, both lock orders,
two concurrent rotations, expiry, and the lock timeout. It fails if `noRollbackFor` or `lockActive`
is removed (checked once by mutation).

**PT:** A ordem é fixa (ADR 0008):

1. `findByTokenHash(sha256(raw))`. Não achou → `InvalidRefreshTokenException`; nada é travado.
2. `lockActive(familyId)`: `SELECT ... FOR NO KEY UPDATE` na linha da família, só se não revogada.
   Espera uma rotação ou revogação simultânea da **mesma sessão**. Vazio (revogada, ou revogada
   enquanto esperávamos) → a mesma exceção, sem revogar.
3. O `now` é lido do `Clock` **depois** do lock, truncado em microssegundos. Depois do lock, para
   que uma rotação que esperou julgue a validade no momento em que roda. Microssegundos, porque o
   PostgreSQL guarda `timestamptz` com microssegundos e o pgjdbc **arredonda** os nanossegundos
   extras: sem truncar, um token que vence dentro do mesmo microssegundo poderia passar na checagem
   do Java, falhar no `expires_at > now` do `markUsed` e ser tratado como reuso, revogando uma
   sessão saudável. Vencido (`expiresAt <= now`, o mesmo limite do `markUsed`) → a mesma exceção,
   **sem revogar e sem `markUsed`**: vencer não é reuso.
4. `markUsed(id, now)`. Sob o lock da família, com a validade já conferida, `0` só pode significar
   "já usado": **reuso**. A família é revogada, uma linha `WARN` é registrada só com o id da família
   (nunca o token, o hash, o usuário ou um email; decisão Q3), e a mesma exceção é lançada.
5. Senão um token novo é emitido na **mesma família** e `Rotation(family.userId, token)` é
   devolvido. O usuário vem da linha travada da família, nunca da requisição.

**PT:** **`noRollbackFor = InvalidRefreshTokenException.class`**: por padrão uma `RuntimeException`
desfaz a transação, o que desfaria a revogação do passo 4, e o atacante com o token mais novo
manteria a sessão. Com `noRollbackFor` a transação faz commit e a exceção ainda chega ao cliente
como `401`. Os outros caminhos de falha não gravaram nada, então o commit deles é inofensivo (e
libera o lock). `REQUIRES_NEW` para a revogação foi descartado: a transação externa segura o lock da
linha da família, então o `UPDATE` interno esperaria pelo próprio chamador até o `lock_timeout`
(veja a emenda do ADR 0008).

**PT:** **`CannotAcquireLockException` nunca é capturada.** Uma espera de lock além do
`lock_timeout` (3 s, ADR 0009) se propaga como `500` mascarado; o token fica intacto (`used_at`
continua nulo), então o cliente pode tentar de novo. Um `401` aqui faria o app apagar uma sessão
saudável porque o banco estava lento.

**PT:** **Os tempos de resposta diferem, e isso é aceito.** Um token desconhecido responde depois de
uma busca indexada, um conhecido depois do lock e dos updates, um reusado depois da revogação também;
o logout ([`revokeFamilyOf`](#revokefamilyof)) difere do mesmo jeito. Os corpos são idênticos, mas o
tempo pode distinguir "este token existe" de "não existe". Isso é inofensivo: um refresh token tem
256 bits aleatórios, então ninguém consegue adivinhar um para sondar, e saber que um token que você
já tem existe não revela nada novo. **Não** adicione atrasos artificiais ou trabalho falso para
igualá-los: custam em toda requisição e não protegem nada. (O login é diferente: lá o segredo é uma
senha de baixa entropia e o email é adivinhável, então ele iguala com um hash falso.)

**PT:** O `RefreshTokenServiceTest` confere a ordem com `InOrder`, o limite da validade, o relógio
lido depois do lock, o truncamento com um relógio em nanossegundos logo antes da validade, a linha
WARN e as anotações. O `RefreshTokenServiceIntegrationTest` prova tudo num
PostgreSQL real com commits reais: o reuso revoga a família e o token mais novo falha, as duas ordens
de lock, duas rotações simultâneas, a validade e o lock timeout. Ele falha se o `noRollbackFor` ou o
`lockActive` forem removidos (conferido uma vez por mutação).

### revokeFamilyOf

Logout. Looks the token up by its hash and, if the server knows it, revokes its family, **even if
the token was already used or is expired** (owner decision Q2): any token the server ever issued
proves the session, and ending a session is never dangerous. An unknown token does nothing; the
revoke count is ignored (already revoked is fine), so logout is idempotent and reveals nothing.

No explicit `lockActive`: the family `UPDATE` itself takes the row lock, so it waits for an open
rotation and then kills the token that rotation issued (ADR 0008). A lock timeout propagates as a
masked `500` (owner decision Q5, the one exception to "logout always 204" in the contract).

Known and unknown tokens take different times; accepted, no artificial delay (see [`rotate`](#rotate)).

**PT:** Logout. Busca o token pelo hash e, se o servidor o conhece, revoga a família dele, **mesmo
que o token já tenha sido usado ou esteja vencido** (decisão do dono, Q2): qualquer token que o
servidor emitiu prova a sessão, e encerrar uma sessão nunca é perigoso. Um token desconhecido não
faz nada; a contagem do revoke é ignorada (já revogada está ok), então o logout é idempotente e não
revela nada.

**PT:** Sem `lockActive` explícito: o próprio `UPDATE` da família pega o lock da linha, então ele
espera uma rotação aberta e depois mata o token que essa rotação emitiu (ADR 0008). Um lock timeout
se propaga como `500` mascarado (decisão Q5, a única exceção ao "logout sempre 204" do contrato).

**PT:** Tokens conhecidos e desconhecidos levam tempos diferentes; aceito, sem atraso artificial (veja
o [`rotate`](#rotate)).

### Rotation

`Rotation(userId, refreshToken)`: what `rotate` returns. `userId` is the owner of the locked family,
so `AuthService` signs the access token for the session's owner without trusting anything the
client sent. Its default `toString` is safe because `IssuedToken` masks its value.

**PT:** `Rotation(userId, refreshToken)`: o que o `rotate` devolve. O `userId` é o dono da família
travada, então o `AuthService` assina o token de acesso para o dono da sessão sem confiar em nada
que o cliente enviou. O `toString` padrão é seguro porque o `IssuedToken` mascara o valor.

### startFamily

Creates the family row (the session) and its first token in one transaction, joining the caller's
when there is one (register). The token is 32 bytes from `SecureRandom` (256 bits, the contract),
encoded as base64url without padding (43 characters, safe in JSON and URLs). Only its SHA-256, in
lowercase hex, is stored (`ck_refresh_tokens_token_hash_hex`); the raw value exists only in the
returned `IssuedToken`. SHA-256 and not bcrypt: the token has 256 bits of entropy, so a fast hash
cannot be brute-forced, and a deterministic hash can be looked up by its unique index (ADR 0002).

**PT:** Cria a linha da família (a sessão) e o primeiro token dela numa transação, entrando na de
quem chama quando existe uma (cadastro). O token tem 32 bytes do `SecureRandom` (256 bits, o
contrato), codificados em base64url sem padding (43 caracteres, seguros em JSON e URLs). Só o
SHA-256 dele, em hex minúsculo, é gravado (`ck_refresh_tokens_token_hash_hex`); o valor cru existe
só no `IssuedToken` devolvido. SHA-256 e não bcrypt: o token tem 256 bits de entropia, então um
hash rápido não pode ser quebrado por força bruta, e um hash determinístico pode ser buscado pelo
índice único (ADR 0002).

## IssuedToken

A token value plus the lifetime it was issued with, returned by `AccessTokenService` and
`RefreshTokenService`. `TokenResponse.bearer` builds `expiresIn`/`refreshExpiresIn` from that same
`ttl`, so the response can never announce a lifetime different from the one in the token or the
row. Its `toString` masks the value: it is a live credential.

**PT:** O valor de um token mais a validade com que foi emitido, devolvido pelo
`AccessTokenService` e pelo `RefreshTokenService`. O `TokenResponse.bearer` monta
`expiresIn`/`refreshExpiresIn` a partir desse mesmo `ttl`, então a resposta nunca anuncia uma
validade diferente da que está no token ou na linha. O `toString` mascara o valor: é uma credencial
viva.

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

## RefreshRequest

Body of [`POST /auth/refresh`](../api-contract.md#post-authrefresh--public) and
[`POST /auth/logout`](../api-contract.md#post-authlogout--public): `@NotBlank` and at most 256
characters counted as code points (`@CodePointLength`, the contract's "chars"). No other format
rule: a non-blank token with an odd shape is simply unknown, answered `401` on refresh and `204` on
logout, so validation never tells a client what a real token looks like. The 256 cap only keeps
oversized input away from hashing and logs. `toString` masks the token: it is a live credential.

**PT:** Corpo de [`POST /auth/refresh`](../api-contract.md#post-authrefresh--public) e
[`POST /auth/logout`](../api-contract.md#post-authlogout--public): `@NotBlank` e no máximo 256
caracteres contados como code points (`@CodePointLength`, os "chars" do contrato). Nenhuma outra
regra de formato: um token não vazio com formato estranho é simplesmente desconhecido, respondido
com `401` no refresh e `204` no logout, então a validação nunca diz a um cliente como é um token
real. O teto de 256 só mantém entradas enormes longe do hash e dos logs. O `toString` mascara o
token: é uma credencial viva.

## InvalidRefreshTokenException

Lives in `shared/error/` with every `ApiException`. `401 invalid-refresh-token` with one fixed
detail for every cause (unknown, expired, revoked, reused): the contract makes them
indistinguishable to the client, and the app reacts the same way to all of them (wipe the session).
No arguments and no cause, so it can never carry the token or a database message. An
`ApiException` and not Spring's `AuthenticationException`: the handler rethrows the latter to the
security layer, where chain 1 would turn it into a `404`. It gets no `WWW-Authenticate` header:
only `unauthorized` asks for a Bearer token.

**PT:** Fica em `shared/error/` junto com toda `ApiException`. `401 invalid-refresh-token` com um
detalhe fixo para toda causa (desconhecido, vencido, revogado, reusado): o contrato as torna
indistinguíveis para o cliente, e o app reage igual a todas (apaga a sessão). Sem argumentos e sem
causa, então nunca pode carregar o token ou uma mensagem do banco. Uma `ApiException` e não a
`AuthenticationException` do Spring: o handler relança esta última para a camada de segurança, onde
a cadeia 1 a transformaria em `404`. Não recebe o header `WWW-Authenticate`: só `unauthorized` pede
um token Bearer.

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
