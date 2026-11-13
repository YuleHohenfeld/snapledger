# Code notes: security and shared infrastructure

The long explanations behind security-related code that lives outside a feature:
`shared/security/`, `shared/error/` pieces that features call, and the database and logging
configuration (`application.properties`, `logback-spring.xml`). The decisions are in the ADRs
([0004](../decisions/0004-jwt-resource-server.md) to
[0009](../decisions/0009-password-hashing-and-database-lock-timeout.md)) and in
[`api/CLAUDE.md`, "Security rules"](../../api/CLAUDE.md#security-rules-non-negotiable).

**PT:** As explicações longas por trás do código ligado a segurança que fica fora de uma feature:
`shared/security/`, partes do `shared/error/` que as features chamam, e a configuração de banco e
de log (`application.properties`, `logback-spring.xml`). As decisões estão nos ADRs
([0004](../decisions/0004-jwt-resource-server.md) a
[0009](../decisions/0009-password-hashing-and-database-lock-timeout.md)) e em
[`api/CLAUDE.md`, "Security rules"](../../api/CLAUDE.md#security-rules-non-negotiable).

## SecurityConfig

### passwordEncoder

Decision record: [ADR 0009](../decisions/0009-password-hashing-and-database-lock-timeout.md)
(encoder, cost, and why register hashes before opening its transaction).

**PT:** Registro da decisão: [ADR 0009](../decisions/0009-password-hashing-and-database-lock-timeout.md)
(encoder, custo, e por que o cadastro gera o hash antes de abrir a transação).

**Plain `BCryptPasswordEncoder`, not `DelegatingPasswordEncoder`.** The delegating encoder adds a
`{bcrypt}` prefix so that a future algorithm (Argon2, scrypt) can coexist with old hashes and be
upgraded on login. That flexibility does not exist in this schema: `users.password_hash` is
`varchar(72)` and `ck_users_password_hash_bcrypt` accepts bcrypt only, so moving to Argon2 (about
97 characters) needs a migration and an ADR anyway. The plain encoder keeps the stored value equal
to the standard bcrypt format that the CHECK describes, and `matches` never depends on a prefix.
The CHECK accepts the prefix too, so switching later needs no data change.

**Cost 10, pinned in `SecurityConfig.BCRYPT_COST`.** 10 is Spring's default and the minimum the
[OWASP Password Storage Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Password_Storage_Cheat_Sheet.html)
recommends for bcrypt; it costs tens of milliseconds per hash on a server. A higher cost slows
offline cracking more, but every login and register pays it on the server CPU, and `/auth/*` has
no rate limit until Phase 4, so a bigger number would make it cheaper to overload the API.
Writing the number keeps a Spring upgrade from changing it silently. The cost is stored inside
each hash (`$2a$10$...`), so a later change applies to new hashes and old ones keep working.

**Where it lives.** In `shared/security/`, not in `auth/`: it is a cryptographic primitive, not an
auth rule, it imports nothing from a feature, and `@WebMvcTest` slices already get it through
`@ImportSecurityStack`. `AuthService` uses it to hash on register and to check on login.

**PT:**

**`BCryptPasswordEncoder` puro, não `DelegatingPasswordEncoder`.** O encoder delegante adiciona um
prefixo `{bcrypt}` para que um algoritmo futuro (Argon2, scrypt) conviva com hashes antigos e seja
atualizado no login. Essa flexibilidade não existe neste esquema: `users.password_hash` é
`varchar(72)` e o `ck_users_password_hash_bcrypt` aceita só bcrypt, então mudar para Argon2 (cerca
de 97 caracteres) exige uma migration e um ADR de qualquer jeito. O encoder puro mantém o valor
gravado igual ao formato bcrypt padrão que o CHECK descreve, e o `matches` nunca depende de um
prefixo. O CHECK também aceita o prefixo, então trocar depois não exige mudar dados.

**Custo 10, fixado em `SecurityConfig.BCRYPT_COST`.** 10 é o padrão do Spring e o mínimo que o
[OWASP Password Storage Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Password_Storage_Cheat_Sheet.html)
recomenda para bcrypt; custa dezenas de milissegundos por hash num servidor. Um custo maior
atrasa mais a quebra offline, mas todo login e cadastro paga esse preço na CPU do servidor, e o
`/auth/*` não tem limite de taxa até a Fase 4, então um número maior deixaria mais barato
sobrecarregar a API. Escrever o número impede que um upgrade do Spring o mude sem aviso. O custo
fica guardado dentro de cada hash (`$2a$10$...`), então uma mudança futura vale para hashes novos e
os antigos continuam funcionando.

**Onde fica.** Em `shared/security/`, não em `auth/`: é uma primitiva criptográfica, não uma regra
de autenticação, não importa nada de uma feature, e as fatias `@WebMvcTest` já o recebem pelo
`@ImportSecurityStack`. O `AuthService` o usa para gerar o hash no cadastro e conferir no login.

## GlobalExceptionHandler

### handleApi

An `ApiException` with the slug `unauthorized` (today `UnauthorizedException`, thrown by
`GET /users/me` when the token's user no longer exists) gets `WWW-Authenticate: Bearer`, exactly
like the 401 the security entry point sends (contract, Errors table; RFC 6750). Both 401s mean
"this access token is not good enough", so the client sees one shape for one meaning. Other 401s
(`invalid-credentials`, later `invalid-refresh-token`) do **not** get the header: the contract does
not list it for them, they are final for the app (no refresh is attempted) and a Bearer challenge
on a login failure would be misleading.

**PT:** Uma `ApiException` com o slug `unauthorized` (hoje a `UnauthorizedException`, lançada pelo
`GET /users/me` quando o usuário do token não existe mais) recebe `WWW-Authenticate: Bearer`,
exatamente como o 401 que o entry point de segurança envia (contrato, tabela Errors; RFC 6750). Os
dois 401 significam "este token de acesso não serve", então o cliente vê uma forma só para um
significado só. Os outros 401 (`invalid-credentials`, depois `invalid-refresh-token`) **não**
recebem o header: o contrato não o lista para eles, eles são finais para o app (nenhum refresh é
tentado) e um desafio Bearer numa falha de login seria enganoso.

## ConstraintViolations

The public way for a service to recognize "this insert hit constraint X" and turn it into a domain
error (`uk_users_email` → `409 email-already-registered`). It reads the name Hibernate extracted
(`org.hibernate.exception.ConstraintViolationException.getConstraintName()`), never the message:
messages change between versions and, without `logServerErrorDetail=false`, would contain values.
The comparison is exact, so `uk_users_email_lower` is not mistaken for `uk_users_email`; anything
else propagates and becomes the masked `500`.

It delegates to `InternalErrors.constraintName`, which already walks the cause chain and the
suppressed exceptions with a bound, so masking in logs and recognition in services cannot
disagree. `InternalErrors` stays package-private (it owns the 500 body and log line, which no
feature should call); this class exposes only the yes/no question. It lives in `shared/error/`
and imports nothing from a feature, so "`shared/` never imports a feature" holds. A graph too big
to inspect answers "no" instead of throwing.

**PT:** O jeito público de um Service reconhecer "este insert bateu na constraint X" e
transformá-lo num erro do domínio (`uk_users_email` → `409 email-already-registered`). Ele lê o
nome que o Hibernate extraiu (`getConstraintName()`), nunca a mensagem: mensagens mudam entre
versões e, sem o `logServerErrorDetail=false`, conteriam valores. A comparação é exata, então
`uk_users_email_lower` não é confundida com `uk_users_email`; todo o resto se propaga e vira o
`500` mascarado.

**PT:** Ele delega ao `InternalErrors.constraintName`, que já percorre a cadeia de causas e as
exceções suprimidas com limite, então o mascaramento nos logs e o reconhecimento nos Services não
podem discordar. O `InternalErrors` continua package-private (ele é dono do corpo e da linha de
log do 500, que nenhuma feature deve chamar); esta classe expõe só a pergunta sim/não. Ela fica em
`shared/error/` e não importa nada de feature, então "o `shared/` nunca importa uma feature"
continua valendo. Um grafo grande demais para inspecionar responde "não" em vez de lançar exceção.

## application.properties

### lock_timeout

Every connection of the pool starts with `lock_timeout = 3s`
(`spring.datasource.hikari.data-source-properties.options=-c lock_timeout=3s`). Without it a
statement waits for a row lock forever: a rotation stuck on a family row (ADR 0008), or a register
waiting on an uncommitted insert of the same email, would hold a pool connection until the other
transaction ends, and enough of them would exhaust the pool for everyone.

- **Why a startup option and not `SET`.** pgjdbc passes `options` to the server when the
  connection opens, so 3 s becomes the session default. With Hikari's `connection-init-sql=SET ...`,
  a later `RESET ALL` (or `DISCARD ALL`) would reset it to the server default, 0 = wait forever.
- **What the client sees.** PostgreSQL raises `55P03 lock_not_available`; Spring translates it to
  `CannotAcquireLockException` (a `PessimisticLockingFailureException`). It is not an
  `ApiException`, so the catch-all answers `500 internal-error`, masked like every database error.
  It must **never** become `401 invalid-refresh-token`: the app would wipe a healthy session
  because the database was slow. Increment 3 (`rotate`) must not catch it.
- **Scope.** Flyway uses the same data source, so a migration that waits more than 3 s for a lock
  fails instead of queueing behind live traffic, which is the safer behavior for a migration.
- **Tests.** `DatabaseConnectionSettingsTest` checks the value on a pool connection and that it
  survives `RESET ALL`; it also ties `LockWaits.LOCK_TIMEOUT` (the constant the timing bounds use)
  to the property. `RefreshTokenFamilyRepositoryTest` holds a family lock past the timeout and
  starts timing only once PostgreSQL reports the wait; `AuthIntegrationTest` makes a register wait
  on an uncommitted duplicate and gets a masked `500` with the fixed detail.
- **Decision:** [ADR 0009](../decisions/0009-password-hashing-and-database-lock-timeout.md), which
  also explains why it is fine for Flyway.

**PT:** Toda conexão do pool começa com `lock_timeout = 3s`. Sem isso um comando espera por um lock
de linha para sempre: uma rotação presa na linha de uma família (ADR 0008), ou um cadastro esperando
um insert sem commit do mesmo email, seguraria uma conexão do pool até a outra transação terminar,
e várias delas esgotariam o pool para todo mundo.

- **PT: Por que uma opção de inicialização e não `SET`.** O pgjdbc passa `options` ao servidor
  quando a conexão abre, então 3 s vira o padrão da sessão. Com o `connection-init-sql=SET ...` do
  Hikari, um `RESET ALL` (ou `DISCARD ALL`) posterior voltaria ao padrão do servidor, 0 = esperar
  para sempre.
- **PT: O que o cliente vê.** O PostgreSQL lança `55P03 lock_not_available`; o Spring o traduz
  para `CannotAcquireLockException` (uma `PessimisticLockingFailureException`). Não é uma
  `ApiException`, então o pega-tudo responde `500 internal-error`, mascarado como todo erro de
  banco. **Nunca** pode virar `401 invalid-refresh-token`: o app apagaria uma sessão saudável porque
  o banco estava lento. A entrega 3 (`rotate`) não pode capturá-la.
- **PT: Alcance.** O Flyway usa o mesmo data source, então uma migration que espera mais de 3 s por
  um lock falha em vez de ficar na fila atrás do tráfego real, o comportamento mais seguro para uma
  migration.
- **PT: Testes.** O `DatabaseConnectionSettingsTest` confere o valor numa conexão do pool e que ele
  sobrevive ao `RESET ALL`; também amarra o `LockWaits.LOCK_TIMEOUT` (a constante que os limites de
  tempo usam) à propriedade. O `RefreshTokenFamilyRepositoryTest` segura o lock de uma família além
  do limite e só começa a medir quando o PostgreSQL informa a espera; o `AuthIntegrationTest` faz
  um cadastro esperar um duplicado sem commit e recebe um `500` mascarado com o detalhe fixo.
- **PT: Decisão:** [ADR 0009](../decisions/0009-password-hashing-and-database-lock-timeout.md), que
  também explica por que isso é aceitável para o Flyway.

## logback-spring.xml

### hibernate value loggers

Login reads password hashes and every flush handles emails and token hashes, so the Hibernate
categories that print **values** are pinned, in addition to `org.hibernate.orm.jdbc.bind`
(bound values) and `org.hibernate.orm.jdbc.error` (driver messages):

| Logger | Prints at | Pinned to |
|---|---|---|
| `org.hibernate.orm.jdbc.extract` | `TRACE`: `extracted value (1:VARCHAR) -> [...]` for every column read | `INFO` |
| `org.hibernate.orm.core` | `DEBUG`: `Listing entities:` with every field of up to 20 entities after a flush (Hibernate's `EntityPrinter`; the flush listener under `org.hibernate.orm.event` decides to list, `core` prints) | `INFO` |

`org.hibernate.orm.results` was checked the same way and prints no values (only initializer
names), so it is not pinned. `DatabaseErrorDetailIntegrationTest` loads a real account with the
whole `org.hibernate` tree at `TRACE` and asserts that neither the email nor the hash appears; each
pin has a positive control that turns that one logger back on and sees the value. Pinning only
stops inheritance: setting one of these loggers explicitly still turns it on, for a deliberate
local investigation.

Cost: `org.hibernate.orm.core` is also where Hibernate logs session and transaction `DEBUG`
lines; troubleshooting them now needs that logger named explicitly. Its `INFO`/`WARN` lines
(version, dialect, warnings) are unchanged.

**PT:** O login lê hashes de senha e todo flush lida com emails e hashes de token, então as
categorias do Hibernate que imprimem **valores** são fixadas, além do `org.hibernate.orm.jdbc.bind`
(valores ligados) e do `org.hibernate.orm.jdbc.error` (mensagens do driver): o
`org.hibernate.orm.jdbc.extract` (em `TRACE`, todo valor lido) e o `org.hibernate.orm.core` (em
`DEBUG`, "Listing entities:" com todos os campos de até 20 entidades depois de um flush), ambos em
`INFO`.

**PT:** O `org.hibernate.orm.results` foi conferido do mesmo jeito e não imprime valores (só nomes
de initializers), então não é fixado. O `DatabaseErrorDetailIntegrationTest` carrega uma conta real
com a árvore inteira `org.hibernate` em `TRACE` e confere que nem o email nem o hash aparecem; cada
fixação tem um controle positivo que religa só aquele logger e vê o valor. Fixar só impede a
herança: configurar um destes loggers explicitamente ainda o liga, para uma investigação local
deliberada.

**PT:** Custo: o `org.hibernate.orm.core` também é onde o Hibernate registra linhas `DEBUG` de
sessão e transação; investigá-las agora exige nomear esse logger explicitamente. As linhas
`INFO`/`WARN` dele (versão, dialeto, avisos) não mudam.

## ContainerErrorDispatchIntegrationTest

The only test that starts a real embedded server (`RANDOM_PORT`): the container's `/error`
forward, the firewall and Tomcat's own logging cannot be exercised with MockMvc (ADR 0007). Every
other `@SpringBootTest`, `AuthIntegrationTest` included, uses `@AutoConfigureMockMvc`.

Why only one: Spring Boot names the engine of every **extra** embedded Tomcat started in the same
JVM `Tomcat-1`, `Tomcat-2`... The wrapper logger that `logback-spring.xml` turns off is
`org.apache.catalina.core.ContainerBase.[Tomcat].[localhost].[/].[dispatcherServlet]`; a second
server logs under `[Tomcat-1]`, which the pin does not cover, so unmasked exceptions could reach
the log, and this class's guard test fails whenever another port-based class runs before it. Rule
A11 of `scripts/claude/api_rules.sh` rejects `RANDOM_PORT`/`DEFINED_PORT` anywhere else.

**PT:** O único teste que sobe um servidor embutido real (`RANDOM_PORT`): o forward do container
para `/error`, o firewall e o log do próprio Tomcat não podem ser exercitados com MockMvc (ADR
0007). Todo outro `@SpringBootTest`, inclusive o `AuthIntegrationTest`, usa `@AutoConfigureMockMvc`.

**PT:** Por que só um: o Spring Boot dá ao engine de todo Tomcat embutido **extra** iniciado na
mesma JVM o nome `Tomcat-1`, `Tomcat-2`... O logger do wrapper que o `logback-spring.xml` desliga é
`org.apache.catalina.core.ContainerBase.[Tomcat].[localhost].[/].[dispatcherServlet]`; um segundo
servidor registra em `[Tomcat-1]`, que a fixação não cobre, então exceções sem máscara poderiam
chegar ao log, e o teste de guarda desta classe falha sempre que outra classe com porta roda antes
dela. A regra A11 do `scripts/claude/api_rules.sh` recusa `RANDOM_PORT`/`DEFINED_PORT` em qualquer
outro lugar.

## LockWaits

Test helper (`src/test/.../support/LockWaits.java`). Concurrency tests wait until PostgreSQL itself
reports a session blocked on a lock (`pg_stat_activity`, `wait_event_type = 'Lock'`) instead of
sleeping and hoping the other thread got there: deterministic, fast, and it fails loudly if the
expected wait never happens. `await(latch)` gives every latch a 10 s deadline so a broken test
fails instead of hanging. `LOCK_TIMEOUT` mirrors the `lock_timeout` property, and
`DatabaseConnectionSettingsTest` fails if they drift. It lives in `support/` so test classes never
import each other.

**PT:** Auxiliar de teste. Os testes de concorrência esperam até o próprio PostgreSQL informar uma
sessão bloqueada num lock (`pg_stat_activity`, `wait_event_type = 'Lock'`) em vez de dormir e torcer
para a outra thread ter chegado lá: determinístico, rápido, e falha de forma clara se a espera
esperada nunca acontecer. O `await(latch)` dá a todo latch um prazo de 10 s, para que um teste
quebrado falhe em vez de travar. O `LOCK_TIMEOUT` espelha a propriedade `lock_timeout`, e o
`DatabaseConnectionSettingsTest` falha se os dois se afastarem. Ele fica em `support/` para que
classes de teste nunca importem umas às outras.
