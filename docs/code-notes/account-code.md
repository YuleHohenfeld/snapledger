# Code notes: account-code

The long explanations behind the `accountcode` feature
(`api/src/main/java/com/yulehohenfeld/snapledger/accountcode/`) and its tables
(`V3__add_users_email_verified_at.sql`, `V4__create_account_codes.sql`). The decisions are in
[ADR 0012](../decisions/0012-account-codes.md); this file explains the code. Endpoints that use it
come in a later step.

**PT:** As explicações longas por trás da feature `accountcode` e das tabelas dela. As decisões
estão na [ADR 0012](../decisions/0012-account-codes.md); este arquivo explica o código. Os endpoints
que a usam (passo 2) estão em [auth](auth.md#passwordresetservice) e [user](user.md#emailverificationservice).

## AccountCode

One row per (user, purpose): the live code. It stores only the HMAC. State changes go through
`issue`, `reissue`, `recordFailedAttempt` and `consume`; there are no setters, so the invariants
(attempts reset on a new code, the use mark cleared) cannot be skipped. It keeps `userId` as a plain
UUID, not a relationship: the feature never needs the `User` entity (and a feature may not touch another
feature's repository). `toString` prints id and purpose only.

**PT:** Uma linha por (usuário, finalidade): o código vivo. Guarda só o HMAC. As mudanças de estado
passam por `issue`, `reissue`, `recordFailedAttempt` e `consume`; não há setters, então as invariantes
(tentativas zeradas num código novo, marca de uso limpa) não podem ser puladas. Guarda o `userId` como
UUID simples, sem relacionamento: a feature nunca precisa da entidade `User`. O `toString` mostra só
id e finalidade.

## CodePurpose

`EMAIL_VERIFICATION` and `PASSWORD_RESET`, stored as strings (`@Enumerated(STRING)`), never ordinals:
reordering the enum must not change the meaning of old rows. The name is part of the hashed input, so
a code is valid for one purpose only, and the CHECK `ck_account_codes_purpose` repeats the list.

**PT:** Gravados como texto, nunca como ordinal: reordenar o enum não pode mudar o sentido de linhas
antigas. O nome entra no hash, então um código vale para uma finalidade só, e o CHECK repete a lista.

### purpose-binding

Without the purpose in the HMAC input, the code of a "verify email" mail could be replayed to reset
the password of the same user if the rows ever got mixed up. With `purpose|userId|code`, the hash
differs for each purpose and user even for the same six digits.

**PT:** Sem a finalidade no HMAC, o código de um email de "verificar email" poderia ser reaproveitado
para redefinir a senha do mesmo usuário. Com `purpose|userId|code`, o hash é diferente por finalidade
e por usuário, mesmo para os mesmos seis dígitos.

## AccountCodeHasher

HMAC-SHA256 in lowercase hex (64 characters, matching `ck_account_codes_code_hash_hex`). A new `Mac`
per call because `Mac` is not thread-safe. `matches` re-hashes the candidate and compares the bytes
with `MessageDigest.isEqual`, which takes the same time wherever the first difference is, so the
response time leaks nothing about the stored hash. The failure branch of `getInstance` throws a
message-free exception: the algorithm is mandatory in every JVM.

**PT:** HMAC-SHA256 em hex minúsculo (64 caracteres). Um `Mac` novo por chamada, porque ele não é
thread-safe. O `matches` refaz o hash do candidato e compara os bytes com `MessageDigest.isEqual`, que
leva o mesmo tempo onde quer que esteja a primeira diferença.

## AccountCodeProperties

Same fail-fast shape as `JwtProperties`: no secret, a non-Base64 secret or fewer than 256 bits stops
startup, and neither the messages nor `toString` quote the secret (the JDK's Base64 error names the
offending character, so it is not kept as a cause). Defaults live in `application.properties`.

**PT:** Mesmo formato fail-fast do `JwtProperties`: sem segredo, segredo que não é Base64 ou com menos
de 256 bits impede a subida, e nem as mensagens nem o `toString` citam o segredo.

## AccountCodeService

### issue

Order: lock the (user, purpose) row, decide, and only then generate and hash the code, so a refused
request costs no random number and no HMAC. A row that exists is refused when `isThrottled` (cooldown
not over, or the hour's quota spent) or when the failure budget is spent, otherwise replaced with
`reissue`. No row: `insertIfAbsent`. It returns the raw code only to the caller, which emails it after
the commit (ADR 0013); the raw code is never stored or logged.

**PT:** Ordem: trava a linha (usuário, finalidade), decide e só então gera e faz o hash do código, então
um pedido recusado não gasta número aleatório nem HMAC. Uma linha existente é recusada quando
`isThrottled` ou quando o orçamento de falhas acabou e, senão, substituída com `reissue`. Sem linha:
`insertIfAbsent`. Devolve o código puro só a quem chama, que o envia por email depois do commit.

### consume

Lock, then the failure budget (spent: `false` without comparing), then `isUsable` (not used, not expired, attempts below the limit), then the
constant-time compare. A wrong guess increments `attempts` and returns `false`; because nothing is
thrown, the caller's transaction commits the increment (ADR 0012 point 6). The attempt check comes
before the compare, so the sixth guess fails even when it is the right code.

**PT:** Lock, depois as verificações do `isUsable` (não usado, não expirado, tentativas abaixo do
limite), depois a comparação em tempo constante. Um palpite errado incrementa `attempts` e devolve
`false`; como nada é lançado, a transação de quem chama confirma o incremento. A checagem de tentativas
vem antes da comparação, então o sexto palpite falha mesmo sendo o código certo.

## AccountCodeRepository

### lock

`PESSIMISTIC_WRITE` (`SELECT ... FOR UPDATE`) on the (user, purpose) row. Call it first in every
transaction that issues or checks a code; it serializes them, so counters and the single-use mark are
exact under concurrency. The wait is capped by `lock_timeout` (3 s) and a timeout surfaces as a masked
`500`, never a domain error (see [security.md](security.md#lock_timeout)).

**PT:** Trava a linha (usuário, finalidade). Chame-o primeiro em toda transação que emite ou confere um
código; ele as serializa, então contadores e a marca de uso único ficam exatos sob concorrência.

### insertIfAbsent

Native `INSERT ... ON CONFLICT (user_id, purpose) DO NOTHING`. A plain `save` hitting
`uk_account_codes_user_purpose` would throw inside the caller's transaction and mark it rollback-only
(PostgreSQL also aborts it), so the "lost the race" case could not be handled. Returning 0 turns it into
a normal, throttled answer. The SQL holds the initial values (attempts 0, one send, window opened now,
failure budget empty); production has no factory, and tests build rows with `support/AccountCodeFixtures`.
It has no `clearAutomatically`: that would detach every entity already loaded in the caller's
transaction (for example a `User`) and silently drop later changes to it; `flushAutomatically` is enough.

**PT:** `INSERT ... ON CONFLICT DO NOTHING` nativo. Um `save` comum que batesse na constraint lançaria
exceção dentro da transação de quem chama e a marcaria como rollback-only. Devolver 0 transforma o
"perdi a corrida" numa resposta normal de limite.

### failure-budget

`failed_window_started_at` and `failed_in_window` count every wrong guess of a (user, purpose) in a fixed
24 h window opened by the first failure. A new code (`reissue`) does not touch them, which is the point:
otherwise 5 attempts x 5 codes an hour = 600 guesses a day. At 10 failures `consume` returns `false`
without comparing (even for the right code) and `issue` returns empty until the window ends; a successful
`consume` clears the budget. The window is fixed, so a burst straddling the boundary could use up to 2x the
budget; at 10 a day this is irrelevant. Numbers: 10 / 1,000,000 a day, about 0.4% a year per account.

**PT:** `failed_window_started_at` e `failed_in_window` contam todo palpite errado de um (usuário,
finalidade) numa janela fixa de 24 h aberta pela primeira falha. Um código novo (`reissue`) não os toca, e
esse é o ponto: senão 5 tentativas x 5 códigos por hora = 600 palpites por dia. Com 10 falhas o `consume`
devolve `false` sem comparar (mesmo com o código certo) e o `issue` devolve vazio até a janela acabar; um
`consume` com sucesso zera o orçamento. Números: 10 / 1.000.000 por dia, cerca de 0,4% ao ano por conta.

### distinct-secrets

`DistinctSecretsValidator` is a bean in `accountcode/config` that reads `AccountCodeProperties` and
`JwtProperties` and throws at startup if the decoded keys are equal (`MessageDigest.isEqual`). It lives in
the feature because `shared` never imports a feature; it never quotes either secret.

**PT:** O `DistinctSecretsValidator` é um bean em `accountcode/config` que lê os dois properties e lança na
subida se as chaves decodificadas forem iguais. Mora na feature porque `shared` nunca importa feature; não
cita nenhum dos segredos.

### resend-window

`window_started_at` and `sends_in_window` live in the same row: the first send opens a one-hour window;
sends inside it count; a send after it starts a new window. `isThrottled` is true inside the cooldown
(`sent_at + 60 s`) or when the quota of 5 is spent inside the window. Fixed, not sliding (ADR 0012 point 7).

**PT:** A janela de reenvio vive na mesma linha: o primeiro envio abre uma janela de uma hora; os envios
dentro dela contam; um envio depois dela abre outra. É fixa, não deslizante.

## AccountEmails

Builds the three messages (verification code, reset code, password changed) in English: plain text
plus a simple HTML copy with no link, image or tracking. The subject never contains the code (subjects
show up in notifications and logs of mail clients). The password-changed message exists so the owner
of an account notices a change they did not make.

**PT:** Monta as três mensagens em inglês: texto puro mais uma cópia HTML simples, sem link, imagem ou
rastreamento. O assunto nunca leva o código (assuntos aparecem em notificações). A mensagem de senha
alterada existe para o dono da conta perceber uma troca que ele não fez.

## V3__add_users_email_verified_at

`users.email_verified_at`, nullable: `null` means not verified. Existing accounts start unverified and
the column needs no default, so the migration is a metadata-only change in PostgreSQL. The API exposes
only the boolean (`emailVerified`), never the instant.

**PT:** Anulável: `null` significa não verificado. As contas existentes começam não verificadas e a
coluna não precisa de default. A API expõe só o booleano.

## V4__create_account_codes

Constraints are named for error handling and tests. The unique `uk_account_codes_user_purpose` has
`user_id` as its first column, so it also serves as the index of the foreign key
`fk_account_codes_user` (the rule "every foreign key has an index" is met without a second index).
The CHECKs repeat what the application guarantees (purpose list, 64 lowercase hex characters, attempts
not negative, at least one send, expiry after send), each proven by a native `INSERT` in
`AccountCodeRepositoryTest`.

**PT:** O unique tem `user_id` como primeira coluna, então também serve de índice da chave estrangeira
(a regra "toda FK tem índice" é cumprida sem um segundo índice). Os CHECKs repetem o que a aplicação
garante, cada um provado por um `INSERT` nativo no `AccountCodeRepositoryTest`.

### uk_account_codes_user_purpose

One live code per (user, purpose): a new request replaces the row instead of adding one, so old codes
cannot be tried and the table stays one row per pair.

**PT:** Um código vivo por (usuário, finalidade): um pedido novo substitui a linha em vez de somar.

## InvalidCodeException

One fixed answer (`400 invalid-code`, fixed detail) for every way a code can fail: wrong, expired,
used, out of attempts, replaced, a code of another purpose, a spent failure budget, an unknown email,
and a per-email confirm limit. If the answers differed, the difference would be an oracle (which
accounts exist, whether a code was ever issued, how close a guess was). It carries no code and no
cause.

**PT:** Uma resposta fixa (`400 invalid-code`, detalhe fixo) para todo jeito de um código falhar: errado,
vencido, usado, sem tentativas, substituído, de outra finalidade, orçamento de falhas esgotado, email
desconhecido e limite de confirmações por email. Se as respostas fossem diferentes, a diferença seria
um oráculo (quais contas existem, se um código foi emitido, quão perto estava um palpite). Ela não
carrega código nem causa.

### step-2-gate

The GATE of step 2 is **satisfied**: both confirm endpoints
([`PasswordResetService`](auth.md#passwordresetservice), [`EmailVerificationService`](user.md#emailverificationservice))
call `consume` inside a `TransactionTemplate`, return a boolean (never throw there) and throw
`InvalidCodeException` only after the commit. `PasswordResetIntegrationTest` and
`EmailVerificationIntegrationTest` read `attempts` and `failed_in_window` from the database after a
wrong code through the real endpoint. When the failure budget is spent, `consume` logs one `WARN`
(`userId` and purpose only; never the email or a code), so a repeated lockout is visible.

**PT:** O PORTÃO do passo 2 está **satisfeito**: os dois endpoints de confirmação chamam o `consume`
dentro de um `TransactionTemplate`, devolvem um boolean (nunca lançam ali) e lançam a
`InvalidCodeException` só depois do commit. Os testes de integração leem `attempts` e
`failed_in_window` no banco depois de um código errado pelo endpoint real. Quando o orçamento de falhas
esgota, o `consume` registra um `WARN` (só `userId` e finalidade; nunca o email nem um código), então um
bloqueio repetido fica visível.

## InvalidResetTokenException

Sibling of `InvalidCodeException` for the reset token (`invalid-reset-token`, 400): unknown,
expired, used or replaced, one fixed answer, no token and no cause carried. It is a different slug
so the app can send the user back to the start instead of asking for the code again.
