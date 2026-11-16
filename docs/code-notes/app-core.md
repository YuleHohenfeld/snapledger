# Code notes: app core

The long explanations behind the Flutter app's cross-cutting code (`app/lib/core/`): configuration,
the HTTP stack, the session and secure storage. The code keeps one short line and links here.
The architecture is in [ADR 0010](../decisions/0010-app-architecture-mvvmc-provider.md); the
session lifecycle (what is stored where, when the session ends) is in
[ADR 0011](../decisions/0011-app-session-lifecycle.md); the behavior the app must follow is in
the contract's [Auth](../api-contract.md#auth) and [Errors](../api-contract.md#errors) sections.

**PT:** As explicações longas por trás do código transversal do app Flutter (`app/lib/core/`):
configuração, a pilha HTTP, a sessão e o armazenamento seguro. O código mantém uma linha curta e
aponta para cá. A arquitetura está no [ADR 0010](../decisions/0010-app-architecture-mvvmc-provider.md);
o ciclo de vida da sessão (o que é guardado onde, quando a sessão termina) está no
[ADR 0011](../decisions/0011-app-session-lifecycle.md); o comportamento que o app precisa seguir
está nas seções [Auth](../api-contract.md#auth) e [Errors](../api-contract.md#errors) do contrato.

## AppConfig

`API_BASE_URL` comes from `--dart-define` and is compiled into the app. It has **no default**: a
default would silently send real users' credentials to the wrong server (or to a developer's
machine) if someone forgot the flag. A missing or unsafe value throws `ConfigException` with a
**code** (`ConfigError`), not a sentence: the screen that shows it is localized, and tests compare
codes, not text.

The rules, in order: not empty; no whitespace (`Uri.tryParse` would percent-encode a space in the
host instead of refusing it); absolute; `http` or `https` only; a host; no user info
(`https://user:pass@host` would put a credential in the binary); no query or fragment (the client
appends `/api/v1/...` to the base, and a `?` or `#` would swallow it). Trailing slashes are removed
so `'$base/api/v1'` never has `//`.

`http://` is accepted only for hosts that exist on the developer's machine (`localhost`,
`127.0.0.1`, and `10.0.2.2`, which is how the Android emulator reaches the host), and **never in a
release build**: tokens and passwords must not travel in clear text over a real network (OWASP
MASVS-NETWORK). `AppConfig.parse` takes `isRelease` as a parameter so tests can check the release
rule; `fromEnvironment` passes Flutter's `kReleaseMode`, a compile-time constant. This is the only
file in `lib/` allowed to contain a URL literal (hook rule D7).

**PT:** O `API_BASE_URL` vem do `--dart-define` e é compilado dentro do app. Ele **não tem valor
padrão**: um padrão mandaria em silêncio as credenciais de usuários reais para o servidor errado
(ou para a máquina de um desenvolvedor) se alguém esquecesse a flag. Um valor ausente ou inseguro
lança `ConfigException` com um **código** (`ConfigError`), não uma frase: a tela que o mostra é
traduzida, e os testes comparam códigos, não texto.

**PT:** As regras, em ordem: não vazio; sem espaços (o `Uri.tryParse` codificaria um espaço no host
em vez de recusá-lo); absoluta; só `http` ou `https`; com host; sem user info
(`https://user:pass@host` colocaria uma credencial no binário); sem query nem fragment (o cliente
acrescenta `/api/v1/...` à base, e um `?` ou `#` engoliria isso). Barras no final são removidas
para que `'$base/api/v1'` nunca tenha `//`.

**PT:** `http://` só é aceito para hosts que existem na máquina do desenvolvedor (`localhost`,
`127.0.0.1` e `10.0.2.2`, que é como o emulador Android enxerga o host), e **nunca num build de
release**: tokens e senhas não podem trafegar em texto puro numa rede real (OWASP MASVS-NETWORK). O
`AppConfig.parse` recebe `isRelease` como parâmetro para os testes checarem a regra de release; o
`fromEnvironment` passa o `kReleaseMode` do Flutter, uma constante de compilação. Este é o único
arquivo em `lib/` que pode conter uma URL literal (regra D7 do hook).

## ApiFailure

Repositories and ViewModels never see Dio: every failed request reaches them as a sealed
`ApiFailure`, so a `switch` over it is checked by the compiler.

- `NetworkFailure`: no HTTP response at all (offline, DNS, timeout, TLS, cancelled). The request
  may not even have reached the server.
- `ProblemFailure`: the server answered. `status` is the HTTP status; `type` is the slug of
  `urn:snapledger:problem:<slug>` mapped to `ProblemType`, which lists **all 14 slugs** of the
  contract's error table plus `unknown`. `about:blank` (statuses without a slug, such as `413`),
  a missing `type`, a slug added by a newer API, or a body that is not JSON all become `unknown`,
  and the app branches on `status`.
- `fieldErrors` keeps **only field names**. The server's `message` texts are English, may change,
  and are not localized; the app shows its own text next to the field
  ([failureMessages](#failuremessages)).
- `errorId` exists only on `500`; it is an opaque id that support can search in the server logs,
  so it is safe to show.
- A **2xx whose body is not the promised JSON object** (empty, broken JSON, an HTML captive portal
  page) is also a `ProblemFailure`, with the real 2xx status and `unknown`. Returning `{}` instead
  would hide a contract break and make a model parser fail later with a confusing error.

`toString()` shows only status and type, never a body, so logging a failure cannot leak data.

**PT:** Repositórios e ViewModels nunca enxergam o Dio: toda requisição que falha chega até eles
como um `ApiFailure` selado (sealed), então um `switch` sobre ele é verificado pelo compilador.

- **PT:** `NetworkFailure`: nenhuma resposta HTTP (offline, DNS, timeout, TLS, cancelada). A
  requisição pode nem ter chegado ao servidor.
- **PT:** `ProblemFailure`: o servidor respondeu. `status` é o status HTTP; `type` é o slug de
  `urn:snapledger:problem:<slug>` convertido em `ProblemType`, que lista **os 14 slugs** da tabela
  de erros do contrato mais `unknown`. `about:blank` (status sem slug, como `413`), `type` ausente,
  um slug criado por uma API mais nova, ou um corpo que não é JSON viram `unknown`, e o app decide
  pelo `status`.
- **PT:** `fieldErrors` guarda **só os nomes dos campos**. Os textos `message` do servidor são em
  inglês, podem mudar e não são traduzidos; o app mostra o próprio texto ao lado do campo
  ([failureMessages](#failuremessages)).
- **PT:** `errorId` só existe no `500`; é um id opaco que o suporte procura nos logs do servidor,
  então é seguro mostrar.
- **PT:** Um **2xx cujo corpo não é o objeto JSON prometido** (vazio, JSON quebrado, uma página
  HTML de portal cativo) também vira `ProblemFailure`, com o status 2xx real e `unknown`. Devolver
  `{}` esconderia uma quebra de contrato e faria o parser do model falhar depois com um erro confuso.

**PT:** O `toString()` mostra só status e type, nunca um corpo, então logar uma falha não vaza dados.

## TokenResponse

The contract's `TokenResponse`, shared by register, login and refresh. It lives in `core/api/`
(not in `features/auth/`) because the [refresher](#apisessionrefresher) in `core/` parses it, and
`core/` never imports a feature. `fromJson` throws `FormatException` (an `Exception`, so callers
can catch it) naming the field, never its value. `toString()` masks both tokens: a stray
`print(response)` or an error report must not leak a credential.

**PT:** O `TokenResponse` do contrato, usado por register, login e refresh. Ele fica em `core/api/`
(e não em `features/auth/`) porque o [refresher](#apisessionrefresher) em `core/` o lê, e `core/`
nunca importa uma feature. O `fromJson` lança `FormatException` (uma `Exception`, então quem chama
pode capturar) citando o campo, nunca o valor. O `toString()` mascara os dois tokens: um
`print(response)` esquecido ou um relatório de erro não pode vazar uma credencial.

## ApiClient

The only object repositories use to call the API, and the only place (besides the interceptor and
the refresher, which live next to it) that catches `DioException`. It exposes what the current
screens need (`getJson`, `postJson`, `postNoContent`); `patchJson`, `putJson` and `delete` arrive
with their first use.

Dio's own JSON decoding is turned off on purpose: every call asks for `<String>` (Dio forces JSON
decoding for any other type argument) and `decodeJsonObject` decodes it. With Dio decoding, a
broken JSON body throws inside Dio **without a response**, which would look like a
`NetworkFailure`; decoding here keeps the real status and lets a malformed 2xx fail loudly as a
`ProblemFailure`. `application/problem+json` and `application/json` are decoded the same way.

There is **no `LogInterceptor`**, in any build: it prints headers and bodies, which include the
`Authorization` header, passwords on login and tokens on refresh (hook rule D3).

**PT:** O único objeto que os repositórios usam para chamar a API, e o único lugar (além do
interceptor e do refresher, que ficam ao lado dele) que captura `DioException`. Ele expõe o que as
telas atuais precisam (`getJson`, `postJson`, `postNoContent`); `patchJson`, `putJson` e `delete`
chegam no primeiro uso.

**PT:** A decodificação JSON do próprio Dio é desligada de propósito: toda chamada pede `<String>`
(o Dio força a decodificação JSON para qualquer outro tipo) e o `decodeJsonObject` decodifica. Com
o Dio decodificando, um corpo JSON quebrado lança dentro do Dio **sem response**, o que pareceria um
`NetworkFailure`; decodificando aqui, o status real é mantido e um 2xx malformado falha alto como
`ProblemFailure`. `application/problem+json` e `application/json` são decodificados do mesmo jeito.

**PT:** **Não existe `LogInterceptor`**, em nenhum build: ele imprime headers e corpos, que incluem
o header `Authorization`, senhas no login e tokens no refresh (regra D3 do hook).

## ApiStack

Factory functions that build every `Dio`. They live in `core/api/` because hook rule D8 forbids
importing `dio` in `lib/app/` (the composition root); `lib/app/` calls these functions and never
sees Dio.

The objects form a cycle if built naively: the interceptor needs the session (to wipe it), the
session needs the refresher (cold start), and the refresher needs HTTP. The cycle is broken by the
build order **`TokenStore` → `buildSessionRefresher` → `SessionNotifier` → `buildApiClient`**: the
refresher has its own Dio and only talks to `TokenStore`, never to the session. When the refresher
ends a session it clears the `TokenStore` itself and returns
[`SessionEnded`](#refreshoutcome); its callers react to that value and update the session state.

Shared options: base URL `{API_BASE_URL}/api/v1`; connect timeout 10 s and receive timeout 20 s
(no send timeout: on the web Dio warns about it for requests without a body); JSON request bodies;
`Accept: application/json, application/problem+json` (the API only produces JSON; naming the
problem type too keeps a strict server from answering `406 not-acceptable` to an error);
**`followRedirects: false`**: the contract has no redirects, and following one would send the
request again (with its `Authorization` header or its refresh token body) to wherever the
`Location` points, outside the interceptor's [origin check](#protected-requests). A `3xx` is
therefore a non-2xx answer and becomes a `ProblemFailure` with that status. (Browsers follow
redirects themselves, so on the web this option has no effect; the origin check still holds for
the requests the app builds.) `buildApiClient` passes the interceptor the API base as a `Uri`,
parsed from the same string as `baseUrl`. Each `buildX` takes an optional `HttpClientAdapter` so
tests replace the network, not the stack.

**PT:** Funções fábrica que montam todo `Dio`. Elas ficam em `core/api/` porque a regra D8 do hook
proíbe importar `dio` em `lib/app/` (a composition root); `lib/app/` chama estas funções e nunca vê
o Dio.

**PT:** Os objetos formam um ciclo se montados de forma ingênua: o interceptor precisa da sessão
(para limpá-la), a sessão precisa do refresher (cold start), e o refresher precisa de HTTP. O ciclo
é quebrado pela ordem de montagem **`TokenStore` → `buildSessionRefresher` → `SessionNotifier` →
`buildApiClient`**: o refresher tem o próprio Dio e só fala com o `TokenStore`, nunca com a sessão.
Quando o refresher encerra uma sessão ele mesmo limpa o `TokenStore` e devolve
[`SessionEnded`](#refreshoutcome); quem o chamou reage a esse valor e atualiza o estado da sessão.

**PT:** Opções comuns: URL base `{API_BASE_URL}/api/v1`; timeout de conexão 10 s e de recebimento
20 s (sem timeout de envio: na web o Dio avisa sobre ele em requisições sem corpo); corpos JSON;
`Accept: application/json, application/problem+json` (a API só produz JSON; citar também o tipo
problem evita que um servidor rígido responda `406 not-acceptable` a um erro);
**`followRedirects: false`**: o contrato não tem redirects, e seguir um mandaria a requisição de
novo (com o header `Authorization` ou o refresh token no corpo) para onde o `Location` apontar, fora
da [checagem de origem](#protected-requests) do interceptor. Por isso um `3xx` é uma resposta não-2xx
e vira `ProblemFailure` com esse status. (Navegadores seguem redirects sozinhos, então na web esta
opção não tem efeito; a checagem de origem continua valendo para as requisições que o app monta.) O
`buildApiClient` passa ao interceptor a base da API como `Uri`, lida da mesma string do `baseUrl`.
Cada `buildX` aceita um `HttpClientAdapter` opcional para os testes trocarem a rede, não a pilha.

## AuthInterceptor

The only code that sets `Authorization` (hook rule D10). It never touches `/auth/*`: those
endpoints are public and ignore the header (contract, ADR 0005), and a `401` from them
(`invalid-credentials`, `invalid-refresh-token`) is final.

**PT:** O único código que coloca o `Authorization` (regra D10 do hook). Ele nunca mexe em
`/auth/*`: esses endpoints são públicos e ignoram o header (contrato, ADR 0005), e um `401` deles
(`invalid-credentials`, `invalid-refresh-token`) é definitivo.

### Protected requests

A request is **protected** (gets the token, may trigger a refresh) only when its final URL
(`options.uri`, already joined with the base URL and normalized by Dio) has the **same scheme,
host and port** as the API base and its path is **under the base path** (`/api/v1/`), and the rest
of the path does not start with `auth/`. Checking the final URL, not the `path` string a caller
passed, matters because Dio accepts absolute URLs: `getJson('https://other.example/x')` would
otherwise carry the user's access token to another server, and a `401` from that server would
rotate the user's refresh token for nothing. The same check catches the API's own auth endpoints
written as absolute URLs (`https://api.../api/v1/auth/login`). `onRequest` first removes any
`Authorization` a caller set, so a non-protected request never carries one. Known limit:
percent-encoded paths (`/api/v1/%61uth/...`) are compared as written; the app never builds them.

**PT:** Uma requisição é **protegida** (recebe o token, pode disparar refresh) só quando a URL final
(`options.uri`, já unida à URL base e normalizada pelo Dio) tem **o mesmo scheme, host e porta** da
base da API, o caminho fica **dentro do caminho base** (`/api/v1/`), e o resto do caminho não começa
com `auth/`. Checar a URL final, e não a string `path` que quem chamou passou, importa porque o Dio
aceita URLs absolutas: `getJson('https://outro.exemplo/x')` levaria o access token do usuário para
outro servidor, e um `401` desse servidor rotacionaria o refresh token à toa. A mesma checagem pega
os endpoints de auth da própria API escritos como URL absoluta (`https://api.../api/v1/auth/login`).
O `onRequest` primeiro remove qualquer `Authorization` que quem chamou tenha colocado, então uma
requisição não protegida nunca leva um. Limite conhecido: caminhos com percent-encoding
(`/api/v1/%61uth/...`) são comparados como escritos; o app nunca os monta.

### onError

The algorithm, step by step:

1. Not a `401` whose `type` is `unauthorized`, or not a [protected](#protected-requests) request
   → pass the error on. Other `401` types and every other status are not this class's business.
2. The request was already retried (`extra` flag) → the **new** token was rejected too, so the
   session is really gone: wipe it and pass the error on. There is never a third request.
3. The access token in memory differs from the one this request was sent with (recorded in
   `extra` by `onRequest`) → another request already refreshed while this one was in flight:
   retry once with the current token, **without** refreshing again. Refreshing here would rotate
   the refresh token a second time for nothing.
4. Otherwise ask the [refresher](#apisessionrefresher). Concurrent `401`s all reach this point
   with the same old token and **share one refresh** (single-flight future), then each retries once.
5. An exhaustive `switch` on the [`RefreshOutcome`](#refreshoutcome): `Refreshed` → retry;
   `SessionEnded` → the refresher already cleared the tokens, so the interceptor calls
   `SessionNotifier.wipe()` to move the app to signed out (the router then shows login) and
   passes the **original** error on; `TemporaryFailure` (`500`, timeout, a newer session took
   over) → the session is kept and the original error goes on.
6. The retry goes through the same `Dio`, so `onRequest` attaches the new token and step 2
   protects it from looping.

Why a shared future and not Dio's `QueuedInterceptor`: the queue serializes **every** error,
including unrelated `404`s, behind a slow refresh; the shared future only makes `401`s wait.

**PT:** O algoritmo, passo a passo:

1. **PT:** Não é um `401` com `type` `unauthorized`, ou não é uma requisição
   [protegida](#protected-requests) → repassa o erro. Outros tipos de `401` e qualquer outro status
   não são assunto desta classe.
2. **PT:** A requisição já foi repetida (flag no `extra`) → o token **novo** também foi rejeitado,
   então a sessão acabou de verdade: limpa e repassa o erro. Nunca existe uma terceira requisição.
3. **PT:** O access token em memória é diferente daquele com que esta requisição foi enviada
   (gravado no `extra` pelo `onRequest`) → outra requisição já fez refresh enquanto esta estava em
   voo: repete uma vez com o token atual, **sem** novo refresh. Um refresh aqui rotacionaria o
   refresh token uma segunda vez à toa.
4. **PT:** Senão pede ao [refresher](#apisessionrefresher). `401`s concorrentes chegam todos aqui
   com o mesmo token antigo e **compartilham um refresh** (future single-flight), depois cada um
   repete uma vez.
5. **PT:** Um `switch` exaustivo sobre o [`RefreshOutcome`](#refreshoutcome): `Refreshed` → repete;
   `SessionEnded` → o refresher já apagou os tokens, então o interceptor chama
   `SessionNotifier.wipe()` para levar o app a deslogado (o router então mostra o login) e repassa
   o erro **original**; `TemporaryFailure` (`500`, timeout, uma sessão mais nova assumiu) → a sessão
   é mantida e o erro original segue.
6. **PT:** A nova tentativa passa pelo mesmo `Dio`, então o `onRequest` anexa o token novo e o
   passo 2 impede um loop.

**PT:** Por que um future compartilhado e não o `QueuedInterceptor` do Dio: a fila serializa
**todo** erro, inclusive `404`s sem relação, atrás de um refresh lento; o future compartilhado só
faz os `401`s esperarem.

## ApiSessionRefresher

Implements `SessionRefresher` (`core/session/`), the interface the session and the interceptor
depend on. It owns a Dio **without** the `AuthInterceptor`: a refresh that went through the
interceptor could trigger another refresh on its own `401` (recursion).

**Single flight**: the first caller starts `POST /auth/refresh`; every caller that arrives while it
runs gets the same future; the future is cleared when it completes, so the next expiry starts a
new one. Two parallel refreshes would be a real bug: rotation makes the first one consume the
token, and the second would present an **already used** token, which the server treats as theft
and revokes the whole session family (ADR 0002).

Outcomes:

| Answer | Session | Returns |
|---|---|---|
| `200` with a valid pair | new pair saved (refresh token first), only if the [epoch](#epoch) did not move | `Refreshed(accessToken)` |
| `401 invalid-refresh-token`, or no stored token | ended: `TokenStore.clear()` (even if its delete fails: the delete stays [pending](#deletepending)) | `SessionEnded` |
| `500`, other `4xx`, other `401` types, timeout, no network, malformed `200`, storage failure | **kept** | `TemporaryFailure` |
| any answer, but the epoch moved meanwhile (a wipe or a new sign-in) | the newer state is left alone | `TemporaryFailure` |

Only `invalid-refresh-token` proves the session is dead. A `500` can come from a busy session row
(ADR 0009) and the contract says "the app may retry"; wiping there would log users out because of
a server hiccup. If the new pair cannot be saved after a `200`, the server has already rotated: the
stored token is now dead. The next refresh presents it, the server sees an already-used token and
records it as **reuse** (it revokes the family and logs it; here it is a storage failure, not
theft), and answers `invalid-refresh-token`, which ends the session cleanly (the user logs in
again; nothing is corrupted).

The epoch check also protects a **newer** session: if the user signed out and in again (or signed
in directly) while an old refresh was in flight, that old refresh must neither overwrite the new
tokens nor wipe them, and it reports `TemporaryFailure` so no caller wipes the new session.

**PT:** Implementa o `SessionRefresher` (`core/session/`), a interface de que a sessão e o
interceptor dependem. Ele tem um Dio **sem** o `AuthInterceptor`: um refresh que passasse pelo
interceptor poderia disparar outro refresh no próprio `401` (recursão).

**PT:** **Single flight**: o primeiro a chamar inicia o `POST /auth/refresh`; todo chamador que
chega enquanto ele roda recebe o mesmo future; o future é limpo ao terminar, então a próxima
expiração começa outro. Dois refreshes paralelos seriam um bug real: com a rotação o primeiro
consome o token, e o segundo apresentaria um token **já usado**, que o servidor trata como roubo e
revoga a família inteira da sessão (ADR 0002).

**PT:** Resultados:

| Resposta | Sessão | Devolve |
|---|---|---|
| `200` com um par válido | novo par salvo (refresh token antes), só se o [epoch](#epoch) não mudou | `Refreshed(accessToken)` |
| `401 invalid-refresh-token`, ou nenhum token salvo | encerrada: `TokenStore.clear()` (mesmo se o delete falhar: ele fica [pendente](#deletepending)) | `SessionEnded` |
| `500`, outros `4xx`, outros tipos de `401`, timeout, sem rede, `200` malformado, falha de armazenamento | **mantida** | `TemporaryFailure` |
| qualquer resposta, mas o epoch mudou nesse meio-tempo (um wipe ou um novo login) | o estado mais novo não é tocado | `TemporaryFailure` |

**PT:** Só o `invalid-refresh-token` prova que a sessão morreu. Um `500` pode vir de uma linha de
sessão ocupada (ADR 0009) e o contrato diz "o app pode tentar de novo"; limpar ali deslogaria
usuários por um soluço do servidor. Se o novo par não puder ser salvo depois de um `200`, o servidor
já rotacionou: o token salvo morreu. O próximo refresh o apresenta, o servidor vê um token já usado
e registra **reuso** (revoga a família e loga; aqui é uma falha de armazenamento, não roubo), e
responde `invalid-refresh-token`, o que encerra a sessão de forma limpa (o usuário entra de novo;
nada fica corrompido).

**PT:** A checagem do epoch também protege uma sessão **mais nova**: se o usuário saiu e entrou de
novo (ou entrou direto) enquanto um refresh antigo estava em voo, esse refresh antigo não pode nem
sobrescrever os tokens novos nem apagá-los, e devolve `TemporaryFailure` para ninguém limpar a
sessão nova.

### RefreshOutcome

`refresh()` returns a sealed `RefreshOutcome` instead of a nullable token. With a null, callers
had to infer "the session ended" from a moved epoch and an empty access token, and the interceptor
and `SessionNotifier.restore` each repeated that inference. Now the refresher, which knows what it
did, says it, and both callers `switch` exhaustively (a fourth case would be a compile error in
both). The refresher still clears the `TokenStore` itself before returning `SessionEnded`, so it
never needs the session (no construction cycle, see [ApiStack](#apistack)); the epoch guard stays
inside `TokenStore` and the refresher. `refresh()` never throws. `Refreshed.toString()` masks the
token.

**PT:** O `refresh()` devolve um `RefreshOutcome` selado em vez de um token anulável. Com um null,
quem chamava precisava deduzir "a sessão acabou" a partir de um epoch alterado e de um access token
vazio, e o interceptor e o `SessionNotifier.restore` repetiam essa dedução cada um. Agora o
refresher, que sabe o que fez, diz isso, e os dois fazem um `switch` exaustivo (um quarto caso seria
erro de compilação nos dois). O refresher continua limpando o `TokenStore` ele mesmo antes de
devolver `SessionEnded`, então nunca precisa da sessão (sem ciclo de construção, ver
[ApiStack](#apistack)); a proteção do epoch fica dentro do `TokenStore` e do refresher. O
`refresh()` nunca lança. O `Refreshed.toString()` mascara o token.

## TokenStore

The **refresh token** is persisted (key `refresh_token`) through `SecureStore`; the **access
token** lives only in memory. The access token is short-lived (15 min) and a cold start gets a new
one with one refresh, so persisting it would add risk (a copy at rest) without benefit. Passwords
are never stored.

**PT:** O **refresh token** é persistido (chave `refresh_token`) pelo `SecureStore`; o **access
token** vive só em memória. O access token dura pouco (15 min) e um cold start ganha um novo com um
refresh, então persisti-lo adicionaria risco (uma cópia em repouso) sem benefício. Senhas nunca são
guardadas.

### save

Writes the refresh token **before** the access token becomes visible in memory. After a rotation
the previous refresh token is already dead on the server; if the app used the new access token and
then crashed before persisting, the next start would present a dead token and the user would be
logged out. If the write throws, the access token is not exposed and the caller gets
`SecureStoreException`. `save` is the sign-in path (a **new** session), so it also moves the
[epoch](#epoch); the refresher uses `saveIfEpoch` instead.

**PT:** Grava o refresh token **antes** de o access token ficar visível em memória. Depois de uma
rotação o refresh token anterior já está morto no servidor; se o app usasse o novo access token e
travasse antes de persistir, o próximo início apresentaria um token morto e o usuário seria
deslogado. Se a escrita lançar, o access token não é exposto e quem chamou recebe
`SecureStoreException`. O `save` é o caminho do login (uma sessão **nova**), então ele também move
o [epoch](#epoch); o refresher usa o `saveIfEpoch`.

### epoch

A counter incremented by every `clear()` and every `save()` (sign-in): it numbers the session.
Whoever starts an operation that may save tokens later (a refresh) reads the epoch first and saves
only if it is unchanged (`saveIfEpoch`). Without it, two races break the session:

- **Resurrection**: the user taps "sign out" while a refresh is in flight; the wipe runs; then the
  refresh answers `200` and saves a fresh pair, and the user is silently signed in again.
- **Old session over a new one**: the user signs in (maybe as another account) while a cold-start
  refresh of the old session is in flight; its `200` would overwrite the new tokens, or its
  `invalid-refresh-token` would clear them. Moving the epoch in `save` makes that refresh a no-op.

`saveIfEpoch` checks before **and after** the write: if the epoch moved during the write, it
deletes what it just wrote, **unless a later write started after it** (a write ticket counts the
writes): then the stored value belongs to that newer sign-in and must stay. Platform writes are
processed in order on iOS/macOS (one serial queue) and Android (one HandlerThread), so the later
write is the one that remains on disk. **Not on web**: `flutter_secure_storage_web` awaits WebCrypto
before writing, so writes can finish out of order; the `TokenStore` mutex (roadmap) is a
prerequisite of the web build. `clear()` empties memory
and moves the epoch **before** the delete, so both hold even when the delete fails.

**PT:** Um contador incrementado a cada `clear()` e a cada `save()` (login): ele numera a sessão.
Quem inicia uma operação que pode salvar tokens depois (um refresh) lê o epoch antes e só salva se
ele não mudou (`saveIfEpoch`). Sem isso, duas corridas quebram a sessão:

- **PT:** **Ressurreição**: o usuário toca em "sair" enquanto um refresh está em voo; o wipe roda;
  depois o refresh responde `200` e salva um par novo, e o usuário volta a estar logado em silêncio.
- **PT:** **Sessão antiga por cima da nova**: o usuário entra (talvez com outra conta) enquanto um
  refresh de cold start da sessão antiga está em voo; o `200` dele sobrescreveria os tokens novos,
  ou o `invalid-refresh-token` dele os apagaria. Mover o epoch no `save` torna esse refresh inócuo.

**PT:** O `saveIfEpoch` checa antes **e depois** da escrita: se o epoch mudou durante a escrita, ele
apaga o que acabou de escrever, **a menos que uma escrita posterior tenha começado depois dela** (um
número de escrita conta as escritas): aí o valor salvo pertence a esse login mais novo e precisa
ficar. As escritas na plataforma são processadas em ordem, então a escrita posterior é a que fica
no disco. O `clear()` esvazia a memória e move o epoch **antes** do delete, então os dois valem
mesmo quando o delete falha.

### deletePending

If the delete inside `clear()` throws, the old refresh token is still on disk although the session
ended. `TokenStore` remembers that in memory (`_deletePending`): while it is set,
`readRefreshToken()` first retries the delete and returns **null whatever happens**, so a cleared
token is never read back (no refresh, no revoke with it). A successful write (a new sign-in)
replaces the value and clears the flag; a failed write keeps it. The same flag is set when the
cleanup delete of `saveIfEpoch` fails.

Residual risk: the flag lives in memory. If the app is killed before any retry succeeds, the next
cold start reads the old token and restores the session the user had left, unless the server
already revoked it (the normal logout revokes it first, so this needs both the revoke and the delete
to fail). Recorded in ADR 0011.

**PT:** Se o delete dentro do `clear()` lançar, o refresh token antigo continua no disco embora a
sessão tenha acabado. O `TokenStore` lembra disso em memória (`_deletePending`): enquanto ele está
ligado, o `readRefreshToken()` primeiro tenta o delete de novo e devolve **null aconteça o que
acontecer**, então um token apagado nunca é lido de volta (nem refresh, nem revoke com ele). Uma
escrita bem-sucedida (um novo login) substitui o valor e desliga a flag; uma escrita que falha a
mantém. A mesma flag é ligada quando o delete de limpeza do `saveIfEpoch` falha.

**PT:** Risco residual: a flag vive em memória. Se o app for encerrado antes de alguma nova tentativa
dar certo, o próximo cold start lê o token antigo e restaura a sessão de que o usuário tinha saído, a
menos que o servidor já a tenha revogado (o logout normal revoga antes, então isso exige que o
revoke e o delete falhem). Registrado no ADR 0011.

## SessionNotifier

The app-wide session state (`ChangeNotifier`, `foundation` only): `unknown` (cold start, not
decided yet), `signedOut`, `signedIn`, plus `restoreFailed`. The router (step 3) redirects only
from this state. It is the only class that changes the state; the interceptor asks it to `wipe()`.

**PT:** O estado de sessão do app inteiro (`ChangeNotifier`, só `foundation`): `unknown` (cold
start, ainda não decidido), `signedOut`, `signedIn`, mais `restoreFailed`. O router (passo 3)
redireciona só a partir deste estado. É a única classe que muda o estado; o interceptor pede a ela
um `wipe()`.

### restore

A cold start runs **one** refresh and switches on its [outcome](#refreshoutcome): `Refreshed` →
`signedIn`; `SessionEnded` (no stored token, or `invalid-refresh-token`) → `signedOut`;
`TemporaryFailure` (offline, `500`, keychain locked) → stay `unknown` with `restoreFailed = true`
and **keep the token**, so a splash screen can offer "try again" instead of logging the user out
because the phone had no signal. If the state stopped being `unknown` while the refresh ran (a
sign-in or a wipe already decided it), the outcome is ignored: an old refresh must not undo a newer
decision. Calls while a restore runs share it, and a restore once the state is known does nothing.

**PT:** Um cold start roda **um** refresh e faz um switch sobre o [resultado](#refreshoutcome):
`Refreshed` → `signedIn`; `SessionEnded` (nenhum token salvo, ou `invalid-refresh-token`) →
`signedOut`; `TemporaryFailure` (offline, `500`, keychain bloqueado) → fica `unknown` com
`restoreFailed = true` e **mantém o token**, para uma tela de splash oferecer "tentar de novo" em vez
de deslogar o usuário porque o celular estava sem sinal. Se o estado deixou de ser `unknown`
enquanto o refresh rodava (um login ou um wipe já o decidiu), o resultado é ignorado: um refresh
antigo não pode desfazer uma decisão mais nova. Chamadas durante um restore o compartilham, e um
restore com o estado já conhecido não faz nada.

### wipe

Clears the tokens and moves to `signedOut`. It **never throws**: if the device storage fails to
delete, memory is already clear and the epoch moved, so the app is signed out now; the delete stays
[pending](#deletepending) and the next read retries it. Throwing here would leave the interceptor
and the logout button in a half-signed-out state.

**PT:** Apaga os tokens e vai para `signedOut`. Ele **nunca lança**: se o armazenamento do aparelho
falhar no delete, a memória já está limpa e o epoch mudou, então o app já está deslogado; o delete
fica [pendente](#deletepending) e a próxima leitura o refaz. Lançar aqui deixaria o interceptor e o
botão de sair num estado meio deslogado.

### signOut

Calls the server's logout (passed in as `revoke`, because `core/` cannot import the auth feature's
repository) with the stored refresh token, waits at most **5 s**, then wipes locally **whatever
happened**. The contract makes logout public and idempotent so it can be best effort; a user who
taps "sign out" offline must still be signed out on this device. Without a stored token there is
nothing to revoke and no request is made.

**PT:** Chama o logout do servidor (recebido como `revoke`, porque `core/` não pode importar o
repositório da feature auth) com o refresh token salvo, espera no máximo **5 s** e depois limpa
localmente **aconteça o que acontecer**. O contrato faz o logout público e idempotente para ele
poder ser melhor esforço; um usuário que toca em "sair" offline ainda precisa sair neste aparelho.
Sem token salvo não há o que revogar e nenhuma requisição é feita.

## DeviceSecureStore

The only wrapper around `flutter_secure_storage` (11.x), alone in `device_secure_store.dart`.
Everything else depends on the `SecureStore` interface and `SecureStoreException` in
`secure_store.dart`, which is pure Dart: `TokenStore`, `SessionNotifier` and `failureMessages`
do not pull the plugin (or `flutter/services.dart`) into their imports, and tests use an in-memory
map. `device_secure_store_test.dart` answers the plugin's method channel with `PlatformException`s
to check the error rules below.

- **iOS**: Keychain with `first_unlock_this_device`. "First unlock" lets the app read the token
  after the user unlocked the phone once since boot (needed for a refresh that runs at start).
  "This device" keeps the item out of iCloud Keychain and out of backups restored on another
  phone: a refresh token copied to a second device would make both share one rotating session,
  and the first rotation would look like theft (reuse detection).
- **Android**: the package defaults of 11.x: a key in the Android Keystore wraps an AES-GCM key
  (RSA-OAEP key wrapping), and `resetOnError: true` makes the plugin erase its own data when it
  can no longer decrypt it (for example a backup restored without the Keystore key). Biometric
  options are not used. Note: Android Auto Backup is still on by default in the manifest; see the
  ADR's open item.
- **Web**: `localStorage` encrypted with WebCrypto; XSS can still read it (ADR 0010).

`read` errors: the iOS "keychain locked" status (`errSecInteractionNotAllowed`, `-25308`, possible
right after a reboot or during app prewarming) is **transient**, so it throws
`SecureStoreException` and the refresher keeps the session. Any other platform error means the
entry is unreadable: it is deleted and `null` is returned, so the user signs in again instead of
the app failing on every start. `write`/`delete` errors throw `SecureStoreException` (code
`write`/`delete`, never the value).

**PT:** O único wrapper do `flutter_secure_storage` (11.x), sozinho em `device_secure_store.dart`.
Todo o resto depende da interface `SecureStore` e do `SecureStoreException` em `secure_store.dart`,
que é Dart puro: `TokenStore`, `SessionNotifier` e `failureMessages` não puxam o plugin (nem o
`flutter/services.dart`) nos seus imports, e os testes usam um mapa em memória. O
`device_secure_store_test.dart` responde ao method channel do plugin com `PlatformException`s para
checar as regras de erro abaixo.

- **PT:** **iOS**: Keychain com `first_unlock_this_device`. "First unlock" deixa o app ler o token
  depois que o usuário desbloqueou o celular uma vez desde o boot (necessário para um refresh no
  início). "This device" mantém o item fora do iCloud Keychain e de backups restaurados em outro
  celular: um refresh token copiado para um segundo aparelho faria os dois dividirem uma sessão com
  rotação, e a primeira rotação pareceria roubo (detecção de reuso).
- **PT:** **Android**: os padrões do pacote na 11.x: uma chave no Android Keystore protege uma
  chave AES-GCM (key wrapping RSA-OAEP), e `resetOnError: true` faz o plugin apagar os próprios
  dados quando não consegue mais decifrá-los (por exemplo um backup restaurado sem a chave do
  Keystore). Opções biométricas não são usadas. Atenção: o Auto Backup do Android continua ligado
  por padrão no manifest; ver o item em aberto do ADR.
- **PT:** **Web**: `localStorage` criptografado com WebCrypto; um XSS ainda consegue lê-lo (ADR 0010).

**PT:** Erros no `read`: o status "keychain bloqueado" do iOS (`errSecInteractionNotAllowed`,
`-25308`, possível logo após reiniciar ou durante o prewarming do app) é **temporário**, então lança
`SecureStoreException` e o refresher mantém a sessão. Qualquer outro erro de plataforma significa
entrada ilegível: ela é apagada e `null` é devolvido, então o usuário entra de novo em vez de o app
falhar em todo início. Erros de `write`/`delete` lançam `SecureStoreException` (código
`write`/`delete`, nunca o valor).

## failureMessages

Turns a failure into localized text; the server's `title`/`detail` are never shown (they are
English, may change, and could reveal internals). Mapping: `NetworkFailure` → `errorNetwork`;
`invalid-credentials` → `errorInvalidCredentials`; `email-already-registered` → `errorEmailTaken`;
`unauthorized` (a `401` the interceptor could not recover without ending the session) →
`errorUnauthorized`; `internal-error` with `errorId` → `errorUnexpectedWithId`;
`SecureStoreException` → `errorStorage`; everything else, including `unknown` and unexpected
errors → `errorUnexpected`.

`validation-error`: `fieldErrorMessage` returns `validationFieldInvalid` for each field the server
rejected, shown under that field. `failureMessage` returns **null** when the form shows every
rejected field (`knownFields`), so the screen does not repeat the error, and `errorValidation`
when some rejected field is not on the form (or no field was named). A null failure gives null,
which keeps the View simple (`if (message != null) Text(message)`).

**PT:** Transforma uma falha em texto traduzido; o `title`/`detail` do servidor nunca aparecem
(são em inglês, podem mudar e poderiam revelar detalhes internos). Mapeamento: `NetworkFailure` →
`errorNetwork`; `invalid-credentials` → `errorInvalidCredentials`; `email-already-registered` →
`errorEmailTaken`; `unauthorized` (um `401` que o interceptor não conseguiu recuperar sem encerrar
a sessão) → `errorUnauthorized`; `internal-error` com `errorId` → `errorUnexpectedWithId`;
`SecureStoreException` → `errorStorage`; todo o resto, inclusive `unknown` e erros inesperados →
`errorUnexpected`.

**PT:** `validation-error`: o `fieldErrorMessage` devolve `validationFieldInvalid` para cada campo
que o servidor rejeitou, exibido sob esse campo. O `failureMessage` devolve **null** quando o
formulário mostra todos os campos rejeitados (`knownFields`), para a tela não repetir o erro, e
`errorValidation` quando algum campo rejeitado não está no formulário (ou nenhum campo foi citado).
Uma falha null dá null, o que mantém a View simples (`if (message != null) Text(message)`).

`email-already-registered` is about one field, so it behaves like a field error: when the form
has an `email` field (`knownFields` contains `email`), `fieldErrorMessage(..., 'email')` returns
`errorEmailTaken` and `failureMessage` returns null, so the message appears once, under the field
the user must change (the register screen). A form without an email field still gets it as a
general message. The pairing lives here, next to the other mappings, so no View has to import
`core/api` to inspect the failure (hook rule D1).

**PT:** O `email-already-registered` é sobre um campo, então se comporta como erro de campo: quando
o formulário tem um campo `email` (`knownFields` contém `email`), o `fieldErrorMessage(..., 'email')`
devolve `errorEmailTaken` e o `failureMessage` devolve null, então a mensagem aparece uma vez, sob o
campo que o usuário precisa mudar (a tela de cadastro). Um formulário sem campo de email ainda a
recebe como mensagem geral. O pareamento fica aqui, junto dos outros mapeamentos, para nenhuma View
precisar importar `core/api` para inspecionar a falha (regra D1 do hook).

## AppNavigator

`AppRoute` lists every location once, as a typed enum, so a screen never spreads path strings
(a typo would only fail at runtime). `AppNavigator` is the interface Controllers use to express a
**navigation intent** (`goTo(AppRoute.register)`): Controllers stay testable with plain `test()`
and a `FakeNavigator`, and never hold a `BuildContext` or a router. The implementation over
GoRouter is [`GoRouterNavigator`](#goroutenavigator) and the `redirect` is [`redirectFor`](#redirectfor). Navigation **after** a sign-in is not an intent: the router's `redirect` reacts to the
`SessionNotifier`, so login and register never navigate on success (one source of truth for
"where may a signed-in user be").

**PT:** O `AppRoute` lista todo endereço uma vez, como um enum tipado, para nenhuma tela espalhar
strings de caminho (um erro de digitação só falharia em tempo de execução). O `AppNavigator` é a
interface que os Controllers usam para expressar uma **intenção de navegação**
(`goTo(AppRoute.register)`): os Controllers continuam testáveis com `test()` simples e um
`FakeNavigator`, e nunca guardam um `BuildContext` ou um router. A implementação sobre o GoRouter
é o [`GoRouterNavigator`](#goroutenavigator) e o `redirect` é o [`redirectFor`](#redirectfor). A navegação
**depois** de um login não é uma intenção: o `redirect` do router reage ao `SessionNotifier`, então
login e cadastro nunca navegam no sucesso (uma única fonte da verdade para "onde um usuário logado
pode estar").

## redirectFor

A pure function `redirectFor(SessionStatus, Uri)` returning the location to go to, or null to stay.
It depends on nothing but the session state and the location, so every rule is a plain unit test
and the router needs no widgets to be checked. Rules:

- **unknown** (cold start, not decided yet): everything goes to `/splash`; a tab path is carried as
  `?from=` so the user returns there once the session is decided.
- **signed out**: `/login` and `/register` stay; the splash and everything else go to `/login`
  (a tab path or the splash's own `from` is carried as `?from=`).
- **signed in**: `/login`, `/register` and `/splash` go to the allowlisted `from`, else `/summary`;
  tabs stay; any other path goes to `/summary` (no framework error page for a typed URL).

`?from=` comes from the address bar (on the web anyone can type it) or a link, so it is untrusted.
`allowedFrom` accepts **only** `/summary`, `/expenses` and `/profile`, with no scheme, host, query,
fragment, `//` prefix or backslash: this blocks open redirects (`https://evil.test`,
`//evil.test`, `javascript:`) and loops (`/login?from=/login`). It is an allowlist, not a
blocklist, so a new kind of bad input is refused by default; a new tab must be added to it on
purpose.

**PT:** Uma função pura `redirectFor(SessionStatus, Uri)` que devolve o endereço para onde ir, ou
null para ficar. Ela depende só do estado da sessão e do endereço, então cada regra é um teste
unitário simples e o router não precisa de widgets para ser verificado. Regras:

- **PT:** **unknown** (cold start, ainda não decidido): tudo vai para `/splash`; o caminho de uma
  aba é levado como `?from=` para o usuário voltar a ela quando a sessão for decidida.
- **PT:** **deslogado**: `/login` e `/register` ficam; o splash e todo o resto vão para `/login`
  (o caminho de uma aba ou o `from` do próprio splash é levado como `?from=`).
- **PT:** **logado**: `/login`, `/register` e `/splash` vão para o `from` da allowlist, senão
  `/summary`; as abas ficam; qualquer outro caminho vai para `/summary` (sem página de erro do
  framework para uma URL digitada).

**PT:** O `?from=` vem da barra de endereço (na web qualquer um pode digitá-lo) ou de um link, então
não é confiável. O `allowedFrom` aceita **só** `/summary`, `/expenses` e `/profile`, sem scheme,
host, query, fragmento, prefixo `//` ou barra invertida: isso bloqueia open redirects
(`https://evil.test`, `//evil.test`, `javascript:`) e loops (`/login?from=/login`). É uma allowlist,
não uma blocklist, então um tipo novo de entrada ruim é recusado por padrão; uma aba nova precisa
ser incluída de propósito.

## AppRouter

`buildRouter(session, routes)` builds the one `GoRouter`: `initialLocation` is `/splash`,
`refreshListenable: session` makes go_router re-run the redirect whenever the `SessionNotifier`
notifies (a sign-in, a wipe or a failed restore moves the user from anywhere), and the `redirect`
just calls `redirectFor(session.status, state.uri)`. It receives the route list instead of
importing it, because the list references feature pages and `core/` never imports features; the
list lives in `lib/app/app_routes.dart`. The router is created **once** by a `Provider` in the
composition root and disposed with it: building it inside a `build` method would create a new
router (and reset the navigation) on every rebuild.

**PT:** `buildRouter(session, routes)` monta o único `GoRouter`: o `initialLocation` é `/splash`, o
`refreshListenable: session` faz o go_router reexecutar o redirect sempre que o `SessionNotifier`
notifica (um login, um wipe ou um restore que falhou move o usuário de qualquer lugar), e o
`redirect` só chama `redirectFor(session.status, state.uri)`. Ele recebe a lista de rotas em vez de
importá-la, porque a lista referencia páginas de features e o `core/` nunca importa features; a
lista fica em `lib/app/app_routes.dart`. O router é criado **uma vez** por um `Provider` na
composition root e descartado com ela: criá-lo dentro de um `build` geraria um router novo (e
zeraria a navegação) a cada rebuild.

## GoRouterNavigator

The real [`AppNavigator`](#appnavigator): `goTo` calls `router.go` (replaces the location, no back
entry) and `push` calls `router.push` (wrapped in `unawaited`, since Controllers do not wait for
the page to close). Controllers only know the interface, so nothing but this file and the
composition root touch `GoRouter` outside `lib/app/`.

**PT:** O [`AppNavigator`](#appnavigator) real: `goTo` chama `router.go` (substitui o endereço, sem
entrada de voltar) e `push` chama `router.push` (com `unawaited`, já que Controllers não esperam a
página fechar). Os Controllers só conhecem a interface, então nada além deste arquivo e da
composition root toca o `GoRouter` fora de `lib/app/`.

## Composition root

`lib/app/` is the only place that knows every layer. `buildAppProviders(config)` lists the
app-wide objects **in dependency order**: `AppConfig`, `SecureStore` (`DeviceSecureStore`),
`TokenStore`, `SessionRefresher`, `SessionNotifier`, `ApiClient` (the factories of `api_stack.dart`
keep `dio` out of `lib/app/`), the `GoRouter`, the `AppNavigator`, and the repositories typed by
their **interface** (`Provider<AuthRepository>`), so a test replaces one with a fake. Each is
created lazily once by Provider; the `secureStore` parameter lets a test use an in-memory store
instead of the keychain.

`SnapLedgerApp` puts those providers above `MaterialApp.router`, so every page can `context.read`
them. `HomeShell` (bottom navigation over `StatefulNavigationShell`) lives in `lib/app/` because the
tab list is app structure and it imports no feature; `app_routes.dart` is the only file tying pages
to paths. `main()` reads `AppConfig.fromEnvironment()` first: a `ConfigException` shows
`ConfigErrorApp` (a plain `MaterialApp` with a message) instead of an app that would call a wrong
or insecure server.

**PT:** O `lib/app/` é o único lugar que conhece todas as camadas. O `buildAppProviders(config)`
lista os objetos do app inteiro **na ordem das dependências**: `AppConfig`, `SecureStore`
(`DeviceSecureStore`), `TokenStore`, `SessionRefresher`, `SessionNotifier`, `ApiClient` (as fábricas
do `api_stack.dart` mantêm o `dio` fora do `lib/app/`), o `GoRouter`, o `AppNavigator` e os
repositórios tipados pela **interface** (`Provider<AuthRepository>`), para um teste trocar um por um
fake. Cada um é criado uma vez, sob demanda, pelo Provider; o parâmetro `secureStore` deixa um teste
usar um armazenamento em memória em vez do keychain.

**PT:** O `SnapLedgerApp` põe esses providers acima do `MaterialApp.router`, então toda página pode
dar `context.read` neles. O `HomeShell` (navegação inferior sobre o `StatefulNavigationShell`) fica
no `lib/app/` porque a lista de abas é estrutura do app e ele não importa nenhuma feature; o
`app_routes.dart` é o único arquivo que liga páginas a caminhos. O `main()` lê primeiro o
`AppConfig.fromEnvironment()`: uma `ConfigException` mostra o `ConfigErrorApp` (um `MaterialApp`
simples com uma mensagem) em vez de um app que chamaria um servidor errado ou inseguro.
