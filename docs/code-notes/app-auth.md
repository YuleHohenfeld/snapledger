# Code notes: app auth

The long explanations behind the Flutter app's login and register screens
(`app/lib/features/auth/`), the `UserModel` they return, and the shared form widgets they use
(`app/lib/core/design/widgets/`). The code keeps one short line and links here. The behavior comes
from the contract's [Auth](../api-contract.md#auth) section; the session that receives the tokens
is in [`app-core.md`](app-core.md#sessionnotifier) and
[ADR 0011](../decisions/0011-app-session-lifecycle.md); the layers are in
[ADR 0010](../decisions/0010-app-architecture-mvvmc-provider.md).

**PT:** As explicações longas por trás das telas de login e cadastro do app Flutter
(`app/lib/features/auth/`), do `UserModel` que elas recebem e dos widgets de formulário
compartilhados que usam (`app/lib/core/design/widgets/`). O código mantém uma linha curta e aponta
para cá. O comportamento vem da seção [Auth](../api-contract.md#auth) do contrato; a sessão que
recebe os tokens está no [`app-core.md`](app-core.md#sessionnotifier) e no
[ADR 0011](../decisions/0011-app-session-lifecycle.md); as camadas estão no
[ADR 0010](../decisions/0010-app-architecture-mvvmc-provider.md).

## UserModel

The contract's `UserResponse`. It lives in `features/profile/_shared/data/` because the profile
feature owns the user; auth imports it (a feature may import another feature's `_shared/data`).
`fromJson` checks every field and throws a `FormatException` that names the **field**, never the
**value**: the value may be an email, and an exception message easily ends up in a crash report.
`DateTime.parse` would put the raw text in its own message, so `tryParse` is used and the error is
rebuilt. `toString` shows the id and currency only; name and email are personal data. Value
equality makes tests and `context.select` comparisons straightforward.

**PT:** O `UserResponse` do contrato. Ele fica em `features/profile/_shared/data/` porque a feature
de perfil é dona do usuário; o auth o importa (uma feature pode importar o `_shared/data` de outra).
O `fromJson` checa cada campo e lança uma `FormatException` que cita o **campo**, nunca o **valor**:
o valor pode ser um email, e a mensagem de uma exceção facilmente acaba num relatório de crash. O
`DateTime.parse` colocaria o texto bruto na própria mensagem, então se usa `tryParse` e o erro é
refeito. O `toString` mostra só o id e a moeda; nome e email são dados pessoais. A igualdade por
valor deixa simples os testes e as comparações do `context.select`.

## AuthResponse

`{ "user": UserResponse, "tokens": TokenResponse }`, the body of register (`201`) and login
(`200`). It reuses `TokenResponse` from `core/api/` (core needs it for the refresh, and core never
imports a feature). A missing or non-object part throws `FormatException` naming it. `toString`
delegates to the two parts, which already mask tokens and personal data.

**PT:** `{ "user": UserResponse, "tokens": TokenResponse }`, o corpo do cadastro (`201`) e do login
(`200`). Reaproveita o `TokenResponse` do `core/api/` (o core precisa dele para o refresh, e o core
nunca importa uma feature). Uma parte ausente ou que não é objeto lança `FormatException` citando-a.
O `toString` delega às duas partes, que já mascaram tokens e dados pessoais.

## Requests

`LoginRequest` and `RegisterRequest` are plain immutable values with `toJson`. `RegisterRequest`
**omits `currency`**: the contract makes it optional with default `BRL`, the register screen has no
currency picker in v1, and sending a hard-coded `"BRL"` would duplicate a server default in the
app (a change on the server would silently not apply). `toString` masks every field: the password
is a secret, name and email are personal data, and a request object printed by accident (an
assertion message, a debugger, a future logger) must not leak them. The values are trimmed by the
ViewModel before the request is built (see [LoginViewModel](#loginviewmodel)).

**PT:** `LoginRequest` e `RegisterRequest` são valores imutáveis simples com `toJson`. O
`RegisterRequest` **omite `currency`**: o contrato a torna opcional com padrão `BRL`, a tela de
cadastro não tem seletor de moeda na v1, e enviar um `"BRL"` fixo duplicaria no app um padrão do
servidor (uma mudança no servidor deixaria de valer em silêncio). O `toString` mascara todo campo:
a senha é segredo, nome e email são dados pessoais, e um objeto de requisição impresso por acidente
(uma mensagem de asserção, um debugger, um logger futuro) não pode vazá-los. Os valores são
aparados pelo ViewModel antes de a requisição ser montada (ver [LoginViewModel](#loginviewmodel)).

## AuthRepository

The interface (`AuthRepository`) is what ViewModels and tests see; `ApiAuthRepository` is the only
code that knows the paths: `POST /auth/register`, `POST /auth/login`, `POST /auth/logout`
(`204`, through `ApiClient.postNoContent`). **Refresh is not here**: it belongs to
`ApiSessionRefresher` in `core/api/`, which uses its own Dio without the interceptor and is shared
by the interceptor and the cold start ([ADR 0011](../decisions/0011-app-session-lifecycle.md)).
`logout` is here so the composition root can pass it to `SessionNotifier.signOut(revoke: ...)`
(core cannot import this repository).

Failures: `ApiClient` already turns every non-2xx and every network error into an `ApiFailure`. A
`2xx` whose JSON is valid but does not match the contract (a missing `tokens`, a wrong type) makes
the model throw `FormatException`; the repository turns it into
`ProblemFailure(status: 201 or 200, type: unknown)`, the same shape `ApiClient` uses for a broken
2xx body. So callers handle **one** failure type, and a contract break shows the generic error
instead of leaving the screen stuck in "submitting" with an uncaught exception. The status is the
one the contract promises for that endpoint (the client only returns a body on 2xx).

**PT:** A interface (`AuthRepository`) é o que ViewModels e testes enxergam; o `ApiAuthRepository` é
o único código que conhece os caminhos: `POST /auth/register`, `POST /auth/login`,
`POST /auth/logout` (`204`, via `ApiClient.postNoContent`). **O refresh não está aqui**: ele
pertence ao `ApiSessionRefresher` no `core/api/`, que usa um Dio próprio sem o interceptor e é
compartilhado pelo interceptor e pelo cold start ([ADR 0011](../decisions/0011-app-session-lifecycle.md)).
O `logout` está aqui para a composition root passá-lo ao `SessionNotifier.signOut(revoke: ...)`
(o core não pode importar este repositório).

**PT:** Falhas: o `ApiClient` já transforma todo não-2xx e todo erro de rede em `ApiFailure`. Um
`2xx` com JSON válido mas fora do contrato (sem `tokens`, tipo errado) faz o model lançar
`FormatException`; o repositório o transforma em `ProblemFailure(status: 201 ou 200, type: unknown)`,
o mesmo formato que o `ApiClient` usa para um corpo 2xx quebrado. Assim quem chama trata **um** tipo
de falha, e uma quebra de contrato mostra o erro genérico em vez de deixar a tela presa em
"enviando" com uma exceção não tratada. O status é o que o contrato promete para aquele endpoint (o
cliente só devolve um corpo em 2xx).

## AuthValidators

Pure functions (`features/auth/_shared/validation/auth_validators.dart`) that mirror the contract's
register and login rules for **fast feedback**; the API remains the authority and its
`validation-error` field names are still shown under the fields. They return an `AuthFieldError`
enum, not a message: the View localizes it, and tests compare values, not English text. They are
shared by both screens, which is why they live in `_shared/validation/`. Each screen's Controller
chooses the rule (`validateLoginPassword` vs `validateRegisterPassword`).

**PT:** Funções puras (`features/auth/_shared/validation/auth_validators.dart`) que espelham as
regras de cadastro e login do contrato para **feedback rápido**; a API continua sendo a autoridade
e os nomes de campo do `validation-error` dela ainda aparecem sob os campos. Elas devolvem um enum
`AuthFieldError`, não uma mensagem: a View o traduz, e os testes comparam valores, não texto em
inglês. São compartilhadas pelas duas telas, por isso ficam em `_shared/validation/`. O Controller
de cada tela escolhe a regra (`validateLoginPassword` vs `validateRegisterPassword`).

### validateName

Ends trimmed first (the server trims before validating, contract), then: not empty; no control
(`\p{Cc}`: newline, tab, NUL), format (`\p{Cf}`: zero-width space, right-to-left override, soft
hyphen) or lone surrogate (`\p{Cs}`) code point, the same three categories as the API's
`NoControlCharactersValidator`; at most **80 code points** (`runes.length`), so an emoji counts as
one, as in the contract. Dart's `String.length` counts UTF-16 units (an emoji is 2), which would
reject valid names. The regex uses Unicode property escapes (`RegExp(..., unicode: true)`), which
Dart supports on the VM and on the web (it compiles to a JavaScript `u` regex); a test covers each
category. Dart's `trim` and Java's `strip` differ in a few exotic whitespace characters; the server
decides those cases.

**PT:** Primeiro as pontas são aparadas (o servidor apara antes de validar, contrato), depois: não
vazio; sem code point de controle (`\p{Cc}`: quebra de linha, tab, NUL), de formatação (`\p{Cf}`:
espaço de largura zero, override direita-para-esquerda, hífen suave) ou surrogate sozinho
(`\p{Cs}`), as mesmas três categorias do `NoControlCharactersValidator` da API; no máximo **80 code
points** (`runes.length`), então um emoji conta como um, como no contrato. O `String.length` do Dart
conta unidades UTF-16 (um emoji vale 2), o que rejeitaria nomes válidos. A regex usa escapes de
propriedade Unicode (`RegExp(..., unicode: true)`), que o Dart suporta na VM e na web (vira uma regex
JavaScript com flag `u`); um teste cobre cada categoria. O `trim` do Dart e o `strip` do Java
diferem em alguns espaços exóticos; o servidor decide esses casos.

### validateEmail

The contract rejects whitespace **anywhere** and does not trim. The app trims only the **ends**
before validating and sending, because a trailing space from the keyboard or autofill is a typing
accident, not a different email; a space **inside** is still an error. Then: at most 254
characters; only printable ASCII `0x21`–`0x7E` (the API's `[!-~]+`: no space, no accent, no
emoji); exactly one `@` with text on both sides. This is deliberately looser than the server's
`@Email`: the client blocks obvious mistakes and never rejects something the server would accept.
The email is **never lowercased** on the client: the server stores and compares in lowercase, and
changing what the user typed would be surprising if the server rules ever change.

**PT:** O contrato rejeita espaço em **qualquer** posição e não apara. O app apara só as **pontas**
antes de validar e enviar, porque um espaço no fim vindo do teclado ou do preenchimento automático é
um acidente de digitação, não outro email; um espaço **no meio** continua sendo erro. Depois: no
máximo 254 caracteres; só ASCII imprimível `0x21`–`0x7E` (o `[!-~]+` da API: sem espaço, sem acento,
sem emoji); exatamente um `@` com texto dos dois lados. É de propósito mais frouxo que o `@Email` do
servidor: o cliente barra erros óbvios e nunca rejeita algo que o servidor aceitaria. O email
**nunca é convertido para minúsculas** no cliente: o servidor guarda e compara em minúsculas, e mudar
o que o usuário digitou surpreenderia se as regras do servidor mudarem.

### validatePassword

Passwords are **never trimmed** (a space is a valid password character) and are measured in
**UTF-8 bytes** (`utf8.encode(p).length`), because bcrypt reads at most 72 bytes: `a` is 1 byte,
`é` 2, an emoji 4. "Blank" (only whitespace) is rejected on both screens, like the API's
`@NotBlank`. Register: 8–72 bytes. Login: at most 72 bytes and **no minimum**: login must never
reveal the password policy, and users with an older, shorter password must still be able to log in
if the policy changes. The helper text says "at least 8 characters" because for typical input
characters and bytes match; the byte rule only matters for accents and emoji, and its error message
is generic ("too long").

**PT:** Senhas **nunca são aparadas** (espaço é um caractere válido de senha) e são medidas em
**bytes UTF-8** (`utf8.encode(p).length`), porque o bcrypt lê no máximo 72 bytes: `a` tem 1 byte,
`é` 2, um emoji 4. "Em branco" (só espaços) é rejeitado nas duas telas, como o `@NotBlank` da API.
Cadastro: 8–72 bytes. Login: no máximo 72 bytes e **sem mínimo**: o login nunca pode revelar a
política de senha, e usuários com uma senha antiga mais curta ainda precisam conseguir entrar se a
política mudar. O texto de ajuda diz "pelo menos 8 caracteres" porque, numa entrada típica,
caracteres e bytes coincidem; a regra de bytes só importa com acentos e emoji, e a mensagem de erro
é genérica ("muito longa").

## LoginViewModel

Business state of the login screen, as a sealed immutable value: `LoginIdle`, `LoginSubmitting`,
`LoginSucceeded`, `LoginFailed(failure)`. `submit` trims the email's ends (never the password),
calls `AuthRepository.login`, then `SessionNotifier.signIn(tokens)`, which **persists the refresh
token before** the app is considered signed in ([ADR 0011](../decisions/0011-app-session-lifecycle.md)).

- **Failures become state**: `ApiFailure` (network, invalid credentials, validation, 500) and
  `SecureStoreException` (the keychain could not save the tokens: the user is not signed in and
  sees `errorStorage`). The field is typed `Exception` because Dart has no union types; only those
  two kinds are caught. The View turns it into text with `failureMessage`/`fieldErrorMessage`.
- **Double submit**: a call while `LoginSubmitting` is ignored (the button is also disabled, but a
  keyboard "done" or a fast double tap can arrive before the rebuild).
- **`LoginSucceeded`** is a fourth state on purpose: after success the router's redirect leaves
  the screen, and until it does the button must stay disabled; going back to `LoginIdle` would
  re-enable it for a frame and allow a second login (a second server session). Submits after
  success are ignored too.
- **Navigation is not here, and not in the Controller**: the redirect reacts to the session
  ([AppNavigator](app-core.md#appnavigator)).
- **Dispose**: a response that arrives after the screen closed does not notify (`_disposed`
  guard). The sign-in itself still happens: the user submitted valid credentials and the server
  already created the session.

**PT:** Estado de negócio da tela de login, como um valor imutável selado: `LoginIdle`,
`LoginSubmitting`, `LoginSucceeded`, `LoginFailed(failure)`. O `submit` apara as pontas do email
(nunca a senha), chama `AuthRepository.login` e depois `SessionNotifier.signIn(tokens)`, que
**persiste o refresh token antes** de o app se considerar logado
([ADR 0011](../decisions/0011-app-session-lifecycle.md)).

- **PT:** **Falhas viram estado**: `ApiFailure` (rede, credenciais inválidas, validação, 500) e
  `SecureStoreException` (o keychain não conseguiu salvar os tokens: o usuário não está logado e vê
  `errorStorage`). O campo é tipado como `Exception` porque o Dart não tem tipos união; só esses dois
  tipos são capturados. A View o transforma em texto com `failureMessage`/`fieldErrorMessage`.
- **PT:** **Envio duplo**: uma chamada durante `LoginSubmitting` é ignorada (o botão também fica
  desativado, mas um "concluir" do teclado ou um toque duplo rápido pode chegar antes do rebuild).
- **PT:** **`LoginSucceeded`** é um quarto estado de propósito: depois do sucesso o redirect do
  router sai da tela, e até isso acontecer o botão precisa continuar desativado; voltar para
  `LoginIdle` o reativaria por um frame e permitiria um segundo login (uma segunda sessão no
  servidor). Envios depois do sucesso também são ignorados.
- **PT:** **A navegação não está aqui, nem no Controller**: o redirect reage à sessão
  ([AppNavigator](app-core.md#appnavigator)).
- **PT:** **Dispose**: uma resposta que chega depois que a tela fechou não notifica (guarda
  `_disposed`). O login em si ainda acontece: o usuário enviou credenciais válidas e o servidor já
  criou a sessão.

## RegisterViewModel

Same shape and rules as [LoginViewModel](#loginviewmodel) (`RegisterIdle`, `RegisterSubmitting`,
`RegisterSucceeded`, `RegisterFailed`), calling `AuthRepository.register`. Name and email have
their ends trimmed; the password is sent as typed. The contract makes register **atomic** (account
and session together), so a failed attempt can simply be submitted again. A `409
email-already-registered` is a failure like any other in the ViewModel; the View shows it under the
email field ([failureMessages](app-core.md#failuremessages)).

**PT:** Mesmo formato e regras do [LoginViewModel](#loginviewmodel) (`RegisterIdle`,
`RegisterSubmitting`, `RegisterSucceeded`, `RegisterFailed`), chamando `AuthRepository.register`.
Nome e email têm as pontas aparadas; a senha vai como foi digitada. O contrato torna o cadastro
**atômico** (conta e sessão juntas), então uma tentativa que falhou pode simplesmente ser enviada de
novo. Um `409 email-already-registered` é uma falha como qualquer outra no ViewModel; a View o mostra
sob o campo de email ([failureMessages](app-core.md#failuremessages)).

## LoginController

Screen-only state: the `Form` key, the two `TextEditingController`s, two `FocusNode`s (the
keyboard's "next" moves from email to password) and `passwordVisible` (a `ValueNotifier<bool>`,
hidden by default). It picks the validation rules for this screen (`validateEmail`,
`validateLoginPassword`), forwards the submit to the ViewModel, and turns "create an account" into
the intent `goTo(AppRoute.register)`. It never navigates on success. `dispose` releases every
controller, focus node and notifier it created; the page calls it from `State.dispose`.

**PT:** Estado só da tela: a chave do `Form`, os dois `TextEditingController`s, dois `FocusNode`s (o
"próximo" do teclado vai do email para a senha) e o `passwordVisible` (um `ValueNotifier<bool>`,
oculto por padrão). Ele escolhe as regras de validação desta tela (`validateEmail`,
`validateLoginPassword`), repassa o envio ao ViewModel e transforma "criar uma conta" na intenção
`goTo(AppRoute.register)`. Nunca navega no sucesso. O `dispose` libera todo controller, focus node e
notifier que ele criou; a página o chama no `State.dispose`.

### onSubmit

`formKey.currentState?.validate()` makes the `Form` show the messages under the fields, but the
**decision** to submit comes from the same pure validators run on the controllers' text. Two
reasons: in a plain unit test there is no `Form` (`currentState` is null) and the rule must still
hold; and the decision does not depend on widgets being mounted. A server error under a field (shown
through `InputDecoration.errorText`) does not block a new submit: only the client rules do, and the
new attempt clears the old failure. Editing any field also clears it: the fields' `onChanged` calls
`onFieldEdited()`, which calls the ViewModel's `clearFailure()` (Failed → Idle, a no-op in any other
state, so an edit during a submit changes nothing). Without it a "this email is already registered"
message would stay under an email the user already changed. The login Controller also listens to its
ViewModel and clears the **password** field when the failure is `invalid-credentials` (a wrong
password is not worth keeping on screen); a network or server error keeps it so the user can retry.

**PT:** O `formKey.currentState?.validate()` faz o `Form` mostrar as mensagens sob os campos, mas a
**decisão** de enviar vem dos mesmos validadores puros rodados sobre o texto dos controllers. Dois
motivos: num teste unitário simples não existe `Form` (`currentState` é null) e a regra ainda
precisa valer; e a decisão não depende de widgets montados. Um erro do servidor sob um campo
(mostrado via `InputDecoration.errorText`) não bloqueia um novo envio: só as regras do cliente
bloqueiam, e a nova tentativa limpa a falha antiga. Editar qualquer campo também a limpa: o `onChanged` dos campos chama `onFieldEdited()`, que chama o `clearFailure()` do ViewModel (Failed → Idle, sem efeito em qualquer outro estado, então uma edição durante um envio não muda nada). Sem isso, uma mensagem "este email já está cadastrado" continuaria sob um email que o usuário já trocou. O Controller do login também escuta o ViewModel e limpa o campo da **senha** quando a falha é `invalid-credentials` (uma senha errada não vale ficar na tela); um erro de rede ou servidor a mantém para o usuário tentar de novo.

## RegisterController

Same as [LoginController](#logincontroller) with three fields (name → email → password on
"next"), the register rules (`validateName`, `validateEmail`, `validateRegisterPassword`) and the
intent `goTo(AppRoute.login)` for "I already have an account".

**PT:** Igual ao [LoginController](#logincontroller) com três campos (nome → email → senha no
"próximo"), as regras de cadastro (`validateName`, `validateEmail`, `validateRegisterPassword`) e a
intenção `goTo(AppRoute.login)` para "já tenho uma conta".

## Pages

`LoginPage` / `RegisterPage` create the screen-scoped ViewModel with
`ChangeNotifierProvider(create: ...)`, so Provider disposes it when the screen leaves the tree. The
dependencies are read with `context.read()` and their type is **inferred from the constructor
parameter** (`auth: context.read()` reads an `AuthRepository`), so the page never imports the
repository file (hook rule D1: a View never sees data access) while the ViewModel still receives
the interface. The Controller is created in `initState` (with `context.read`, never `watch`) and
disposed in `dispose`.

`LoginForm` / `RegisterForm` read the state with `context.select`, so only the form rebuilds. Where
an error goes:

- client rule failed → the field's `validator` message, localized from `AuthFieldError`;
- server `validation-error` naming a field on the form → `validationFieldInvalid` under that field
  (never the server text);
- `email-already-registered` on register → `errorEmailTaken` under the email field;
- anything else (invalid credentials, network, storage, 500 with `errorId`, a rejected field that
  is not on the form) → the `FormErrorBanner` above the fields.

The `AuthFieldError` → text switch lives once in `_shared/presentation/auth_field_error_text.dart`
(`authFieldErrorText`), used by both forms: it is exhaustive, so a new enum value fails to compile
there. The limits in the messages (254, 80, 8) are passed as an `int` placeholder from the validator
constants, so the text and the rule cannot drift apart. Both pages use `CenteredFormScaffold` (no
app bar: a full-screen form centered at a readable width) under a `BrandHeader`; each form starts
with its own headline and supporting text, and ends with a `PromptLinkRow` ("Don't have an account?
[Create one]"). Email fields set `enableSuggestions: false` (an
address is not a word to autocomplete).

**PT:** `LoginPage` / `RegisterPage` criam o ViewModel com escopo da tela com
`ChangeNotifierProvider(create: ...)`, então o Provider o descarta quando a tela sai da árvore. As
dependências são lidas com `context.read()` e o tipo delas é **inferido pelo parâmetro do
construtor** (`auth: context.read()` lê um `AuthRepository`), então a página nunca importa o arquivo
do repositório (regra D1 do hook: uma View nunca enxerga acesso a dados) e o ViewModel continua
recebendo a interface. O Controller é criado no `initState` (com `context.read`, nunca `watch`) e
descartado no `dispose`.

**PT:** `LoginForm` / `RegisterForm` leem o estado com `context.select`, então só o formulário é
reconstruído. Para onde vai cada erro:

- **PT:** regra do cliente falhou → a mensagem do `validator` do campo, traduzida a partir do
  `AuthFieldError`;
- **PT:** `validation-error` do servidor citando um campo do formulário → `validationFieldInvalid`
  sob esse campo (nunca o texto do servidor);
- **PT:** `email-already-registered` no cadastro → `errorEmailTaken` sob o campo de email;
- **PT:** todo o resto (credenciais inválidas, rede, armazenamento, 500 com `errorId`, um campo
  rejeitado que não está no formulário) → o `FormErrorBanner` acima dos campos.

**PT:** O switch `AuthFieldError` → texto fica uma vez em `_shared/presentation/auth_field_error_text.dart`
(`authFieldErrorText`), usado pelos dois formulários: ele é exaustivo, então um valor novo no enum
falha na compilação ali. Os limites nas mensagens (254, 80, 8) entram como placeholder `int` vindo
das constantes do validador, então texto e regra não se desencontram. As duas páginas usam o
`CenteredFormScaffold` (sem app bar: um formulário em tela cheia centralizado numa largura legível)
abaixo de um `BrandHeader`; cada formulário começa com seu título e texto de apoio, e termina com
um `PromptLinkRow` ("Não tem conta? [Criar]"). Os campos de
email usam `enableSuggestions: false` (um endereço não é uma palavra para autocompletar).

## Design widgets

Shared, logic-free widgets in `core/design/widgets/`, usable by any feature:

- `AppTextField`: a `TextFormField` with a label. Client errors come from `validator`; a server
  error comes as `errorText` and is shown only while the validator passes (Flutter's
  `TextFormField` overrides `decoration.errorText` with the validator's message when there is one).
  `forceErrorText` was not used: it makes `validate()` fail, which would block a corrected resubmit.
- `PasswordField`: hidden by default (`obscureText`), a show/hide `IconButton` whose tooltip is
  also its accessibility label, `autocorrect` and `enableSuggestions` off (keyboards must not learn
  or suggest the password), `keyboardType: visiblePassword`, and the autofill hint chosen by the
  screen (`password` on login, `newPassword` on register, so password managers offer to generate
  and save one). The visibility flag belongs to the Controller (`ValueListenable<bool>`).
- `ClearsErrorOnEdit` (mixin used by `AppTextField` and `PasswordField`): the validator message
  disappears on the first edit of that field and comes back only on the next `Form.validate()`
  (submit). How: `onChanged` calls `FormFieldState.validate()` with the validator silenced for
  that one call (it returns null, so the message clears), then un-silences it. Why not
  `AutovalidateMode`: `onUserInteraction` *shows* errors while typing (the opposite), and
  `FormFieldState.reset()` would also wipe the text. No validation on unfocus: submit-only is
  predictable. Server errors clear through `clearFailure` (`onFieldEdited`).
- `BrandHeader`: icon in a `primaryContainer` circle, `AppBrand.name` and the tagline; the icon is
  excluded from semantics (decoration).
- `PromptLinkRow`: plain text plus a `TextButton` in a `Wrap`, so it breaks lines on narrow screens
  or large fonts instead of overflowing.
- Both fields take an optional `prefixIcon`. The look (filled, radius 12, 52 px buttons) lives in
  `AppTheme` (`InputDecorationTheme`, `FilledButtonTheme`), not in the widgets, so light and dark
  share it.
- `BusyButton`: disabled with a spinner while busy, so a second tap cannot start a second request.
- `FormErrorBanner`: a form-level error in the error container colors, marked as a live region so
  screen readers announce it when it appears.

**PT:** Widgets compartilhados e sem lógica em `core/design/widgets/`, usáveis por qualquer feature:

- **PT:** `AppTextField`: um `TextFormField` com rótulo. Erros do cliente vêm do `validator`; um erro
  do servidor vem como `errorText` e só aparece enquanto o validator passa (o `TextFormField` do
  Flutter substitui o `decoration.errorText` pela mensagem do validator quando há uma). O
  `forceErrorText` não foi usado: ele faz o `validate()` falhar, o que bloquearia um reenvio corrigido.
- **PT:** `PasswordField`: oculto por padrão (`obscureText`), um `IconButton` mostrar/ocultar cujo
  tooltip é também o rótulo de acessibilidade, `autocorrect` e `enableSuggestions` desligados (o
  teclado não pode aprender nem sugerir a senha), `keyboardType: visiblePassword` e a dica de
  preenchimento escolhida pela tela (`password` no login, `newPassword` no cadastro, para
  gerenciadores de senha oferecerem gerar e salvar uma). A flag de visibilidade pertence ao
  Controller (`ValueListenable<bool>`).
- **PT:** `ClearsErrorOnEdit` (mixin usado por `AppTextField` e `PasswordField`): a mensagem do
  validator some na primeira edição daquele campo e só volta no próximo `Form.validate()` (envio).
  Como: o `onChanged` chama `FormFieldState.validate()` com o validator silenciado só naquela
  chamada (retorna null, então a mensagem limpa) e depois o reativa. Por que não `AutovalidateMode`:
  `onUserInteraction` *mostra* erros enquanto digita (o oposto), e `FormFieldState.reset()` também
  apagaria o texto. Sem validação ao perder o foco: só no envio é previsível. Erros do servidor
  limpam via `clearFailure` (`onFieldEdited`).
- **PT:** `BrandHeader`: ícone num círculo `primaryContainer`, `AppBrand.name` e o slogan; o ícone
  fica fora da semântica (decoração).
- **PT:** `PromptLinkRow`: texto simples mais um `TextButton` num `Wrap`, que quebra linha em telas
  estreitas ou fontes grandes em vez de estourar.
- **PT:** Os dois campos aceitam um `prefixIcon` opcional. O visual (preenchido, raio 12, botões de
  52 px) mora no `AppTheme` (`InputDecorationTheme`, `FilledButtonTheme`), não nos widgets, então
  claro e escuro compartilham.
- **PT:** `BusyButton`: desativado com um spinner enquanto ocupado, para um segundo toque não
  iniciar uma segunda requisição.
- **PT:** `FormErrorBanner`: um erro do formulário nas cores de error container, marcado como live
  region para leitores de tela o anunciarem quando aparece.

## Orphan session

If the API accepts a login or registration but the device cannot save the tokens
(`SecureStoreException`), the server already holds a session nobody will ever use. The ViewModel
shows the storage error first, then calls `logout(refreshToken)` best effort (5 s timeout, any
error ignored): the account stays clean and the user simply tries again. If the revoke also fails,
the session just expires on the server (30 days). An API failure never reaches this branch, because
there is nothing to revoke.

**PT:** Se a API aceita um login ou cadastro mas o aparelho não consegue salvar os tokens
(`SecureStoreException`), o servidor já guarda uma sessão que ninguém vai usar. O ViewModel mostra
primeiro o erro de armazenamento e depois chama `logout(refreshToken)` com melhor esforço (timeout de
5 s, qualquer erro ignorado): a conta fica limpa e o usuário só tenta de novo. Se o revoke também
falhar, a sessão simplesmente expira no servidor (30 dias). Uma falha da API nunca chega a esse
ramo, porque não há nada para revogar.

## SplashViewModel

The splash is the first screen: the router holds every user there while the session is `unknown`.
`start()` awaits `session.restore()` (one refresh, shared with any concurrent caller). With a
verdict (signed in or out) the router's redirect leaves the splash, so the ViewModel does nothing
more. Without one (`TemporaryFailure`: offline or a server error, the session may be fine) the
status stays `unknown` and the state becomes `SplashRestoreFailed`: the page offers **Try again**
(`retry()` goes back to the spinner and restores again) and **Sign in again** (`signInAgain()` wipes
the stored session, the status becomes signed out and the redirect opens the login). The user is
never sent to login just because the network was down. The state is not notified when it does not
change, because `start()` runs from `initState` and a notification during build would throw.

**PT:** O splash é a primeira tela: o router segura todo usuário ali enquanto a sessão é `unknown`.
O `start()` espera o `session.restore()` (um refresh, compartilhado com qualquer chamada
concorrente). Com um veredito (logado ou deslogado) o redirect do router sai do splash, então o
ViewModel não faz mais nada. Sem veredito (`TemporaryFailure`: offline ou erro do servidor, a sessão
pode estar boa) o status continua `unknown` e o estado vira `SplashRestoreFailed`: a página oferece
**Tentar de novo** (o `retry()` volta ao spinner e restaura de novo) e **Entrar novamente** (o
`signInAgain()` apaga a sessão guardada, o status vira deslogado e o redirect abre o login). O
usuário nunca é mandado ao login só porque a rede caiu. O estado não é notificado quando não muda,
porque o `start()` roda no `initState` e uma notificação durante o build lançaria erro.

## PasswordResetViewModel

One screen, three steps, one sealed state: `PasswordResetEnterEmail` → `PasswordResetEnterCode(email)`
→ `PasswordResetDone`. The email lives **only** in the ViewModel state: it is never put in a URL or
in a route `extra` (a URL ends up in history, logs and screenshots, and the reset has no deep link),
so closing the screen forgets it.

- `requestCode(email)`: any `202` advances to the code step, even for an email with no account,
  because the API answers the same bytes for both and the screen must not reveal the difference
  (the intro says "*If* an account exists for ..."). A failure (network, `429` per IP, validation)
  stays on step 1 with the failure in the state.
- `confirm(code, newPassword)`: success → `PasswordResetDone` (the server revoked every session,
  and the screen says so); `invalid-code` stays on step 2 and the View shows it under the code
  field; `429` is a banner. The typed code is **kept** so the user can fix one digit.
- `resend()`: asks for a new code, only when the cooldown reached 0. Even a refused resend restarts
  the 60 s wait.
- `clearFailure()` runs on any edit, so a stale error disappears with the first keystroke.
- The 60 s countdown is a [`ResendCooldown`](#resendcooldown) owned by the ViewModel; the screen only
  reads `cooldownSeconds`. A submit cannot run twice (`busy` ignores a second call) and nothing
  notifies or starts a timer after `dispose`.

**PT:** Uma tela, três passos, um estado selado: `PasswordResetEnterEmail` →
`PasswordResetEnterCode(email)` → `PasswordResetDone`. O email vive **só** no estado do ViewModel:
nunca vai numa URL nem num `extra` da rota (uma URL vai para histórico, logs e capturas de tela, e
a troca de senha não tem deep link), então fechar a tela o esquece.

- **PT:** `requestCode(email)`: todo `202` avança para o passo do código, mesmo para um email sem
  conta, porque a API responde os mesmos bytes nos dois casos e a tela não pode revelar a diferença
  (o texto diz "*Se* existir uma conta para ..."). Uma falha (rede, `429` por IP, validação) fica no
  passo 1 com a falha no estado.
- **PT:** `confirm(code, newPassword)`: sucesso → `PasswordResetDone` (o servidor revogou todas as
  sessões, e a tela diz isso); `invalid-code` fica no passo 2 e a View o mostra sob o campo do
  código; `429` é um banner. O código digitado é **mantido** para o usuário corrigir um dígito.
- **PT:** `resend()`: pede um novo código, só quando a espera chegou a 0. Até um reenvio recusado
  reinicia a espera de 60 s.
- **PT:** `clearFailure()` roda em qualquer edição, então um erro antigo some na primeira tecla.

Added in the fix round:

- `backToEmail()` ("Use a different email" on the code step): cancels the cooldown and emits
  `PasswordResetEnterEmail`. The email stays in the Controller's text field so the user edits it
  instead of retyping; the typed code and new password are cleared (`onUseDifferentEmail`).
- The code and the new password are cleared from their controllers as soon as the state is `Done`
  and in `onBackToLogin`, so a secret does not outlive the flow in memory.

**PT:** Adicionado na rodada de correções:

- **PT:** `backToEmail()` ("Usar outro email" no passo do código): cancela a espera e emite
  `PasswordResetEnterEmail`. O email continua no campo do Controller para o usuário editá-lo em vez
  de digitar de novo; o código e a nova senha digitados são limpos (`onUseDifferentEmail`).
- **PT:** O código e a nova senha são limpos dos controllers assim que o estado é `Done` e no
  `onBackToLogin`, para um segredo não sobreviver ao fluxo na memória.
- **PT:** A contagem de 60 s é um [`ResendCooldown`](#resendcooldown) do ViewModel; a tela só lê
  `cooldownSeconds`. Um envio não roda duas vezes (`busy` ignora a segunda chamada) e nada notifica
  nem inicia timer depois do `dispose`.

## ResendCooldown

A tiny counter (`start()`, `cancel()`, `remaining`) shared by the two code ViewModels. It counts
**ticks**, not wall-clock time: the ticker is injectable (default `Timer.periodic`), so tests use
`fake_async` and a short duration. `ResendCodeButton` is stateless and only draws `remaining`
("Resend code" / "Resend in 0:42"); a timer inside a widget would be business state on the screen
side and untestable without pumping time.

**PT:** Um contador minúsculo (`start()`, `cancel()`, `remaining`) compartilhado pelos dois
ViewModels de código. Ele conta **ticks**, não tempo de relógio: o ticker é injetável (padrão
`Timer.periodic`), então os testes usam `fake_async` e uma duração curta. O `ResendCodeButton` é
stateless e só desenha o `remaining` ("Reenviar código" / "Reenviar em 0:42"); um timer dentro do
widget seria estado de negócio do lado da tela e impossível de testar sem avançar o tempo.

The 60 s is a **client guess** (it mirrors the API's resend cooldown): the server wait
(`Retry-After`) may differ, for example when the hourly quota refused the send. The button can thus
be enabled before the server accepts; the answer is then a `429` banner and a new wait. `cancel()`
also zeroes `remaining`, so a cancelled wait never shows a stale "Resend in 0:42".

**PT:** Os 60 s são um **chute do cliente** (espelha a espera de reenvio da API): a espera do
servidor (`Retry-After`) pode ser outra, por exemplo quando a cota por hora recusou o envio. O botão
pode então habilitar antes de o servidor aceitar; a resposta é um banner de `429` e uma nova espera.
O `cancel()` também zera o `remaining`, então uma espera cancelada nunca mostra um "Reenviar em 0:42"
velho.

## VerifyEmailViewModel

States: `VerifyEmailLoading` (loads `GET /users/me`, which gives the address), `VerifyEmailLoadFailed`
(retry), `VerifyEmailReady(email, busy, failure)` and `VerifyEmailVerified(user)`. An account that is
already verified goes straight to `Verified` and sends nothing.

- Opened **from the profile**: after loading, `sendCode()` runs (the user asked to verify and has no
  code yet). A `429` (a code was sent recently) is a banner and still starts the 60 s wait.
- Opened **right after register**: the API already emailed a code, so the screen does **not** send
  another (it would be refused or waste the hourly quota); only the cooldown starts. Resend is offered.
- `confirm(code)`: `invalid-code` is a field error under the code; success shows the verified
  message with **Continue**.
- `skip()` clears the [pending flag](#pending-verification). The Controller then leaves: `goTo(summary)`
  after register (the screen replaced the stack), `pop()` when it was pushed from the profile.

**PT:** Estados: `VerifyEmailLoading` (carrega `GET /users/me`, que dá o endereço),
`VerifyEmailLoadFailed` (tentar de novo), `VerifyEmailReady(email, busy, failure)` e
`VerifyEmailVerified(user)`. Uma conta já verificada vai direto para `Verified` e não envia nada.

- **PT:** Aberta **pelo perfil**: depois de carregar, roda o `sendCode()` (o usuário pediu para
  verificar e ainda não tem código). Um `429` (um código foi enviado há pouco) é um banner e ainda
  inicia a espera de 60 s.
- **PT:** Aberta **logo após o cadastro**: a API já enviou um código, então a tela **não** envia
  outro (seria recusado ou gastaria a cota horária); só a espera começa. O reenvio é oferecido.
- **PT:** `confirm(code)`: `invalid-code` é um erro de campo sob o código; o sucesso mostra a
  mensagem de verificado com **Continuar**.
- **PT:** `skip()` limpa a [flag pendente](#pending-verification). O Controller então sai:
  `goTo(summary)` após o cadastro (a tela substituiu a pilha), `pop()` quando foi empilhada pelo perfil.

## Pending verification

Owner decision (option B): right after a successful register the app shows the Verify email screen,
with **Skip for now**. To keep "only the redirect navigates on auth success", register does not
navigate. `RegisterViewModel` calls `PendingVerification.begin()` **before** `session.signIn`, so
the redirect that the sign-in triggers already sees the flag and sends the user to `/verify-email`
instead of `/summary` (a flag set after would flash the summary first). `PendingVerification` is a
tiny app-wide `ChangeNotifier` in `core/session/`; the router listens to it too
(`Listenable.merge`). It is one-shot and in-memory: `skip()` clears it, and it clears itself when the
session ends (so a later login never lands on the verification) and when saving the tokens fails
(`SecureStoreException`). While it is set, a signed-in user cannot leave `/verify-email` by typing
another URL. `/verify-email` is a **top-level** route (no bottom bar), so the same page works pushed
from the profile and as the landing after register; `VerifyEmailViewModel.afterRegister` remembers
which one it was.

**PT:** Decisão do dono (opção B): logo após um cadastro bem-sucedido o app mostra a tela de verificar
email, com **Pular por enquanto**. Para manter "só o redirect navega no sucesso de auth", o cadastro
não navega. O `RegisterViewModel` chama `PendingVerification.begin()` **antes** do `session.signIn`,
então o redirect que o login dispara já enxerga a flag e manda para `/verify-email` em vez de
`/summary` (uma flag ligada depois piscaria o resumo primeiro). O `PendingVerification` é um
`ChangeNotifier` minúsculo do app inteiro em `core/session/`; o router o escuta também
(`Listenable.merge`). É de uso único e só em memória: o `skip()` o limpa, ele se limpa quando a
sessão termina (um login futuro nunca cai na verificação) e quando salvar os tokens falha
(`SecureStoreException`). Enquanto ligada, um usuário logado não sai de `/verify-email` digitando
outra URL. `/verify-email` é uma rota de **nível raiz** (sem barra inferior), então a mesma página
serve empilhada pelo perfil e como destino após o cadastro; o `VerifyEmailViewModel.afterRegister`
lembra qual foi.

Hardening (fix round): `RegisterViewModel` clears the flag in a `finally` whenever the register does
not end signed in (any error, even an unexpected one, not only `SecureStoreException`).
`LoginViewModel` clears it **before** `signIn`, so a stale flag can never pin a normal login to the
verification. The flag is **in memory only**: a killed app opens the summary, and the Profile banner
("Verify your email") covers the pending verification. The secondary button reads **Skip for now**
after register and **Back** (`verifyEmailBack`, it pops) when opened from the profile.

**PT:** Reforço (rodada de correções): o `RegisterViewModel` limpa a flag num `finally` sempre que o
cadastro não termina logado (qualquer erro, até um inesperado, não só `SecureStoreException`). O
`LoginViewModel` a limpa **antes** do `signIn`, então uma flag velha nunca prende um login normal na
verificação. A flag vive **só em memória**: um app morto abre o resumo, e o banner do Perfil ("Verifique
seu email") cobre a verificação pendente. O botão secundário diz **Pular por enquanto** após o cadastro
e **Voltar** (`verifyEmailBack`, faz pop) quando aberta pelo perfil.

## CodeField

`CodeField` (in `core/design/widgets/`) is the 6-digit input: `FilteringTextInputFormatter.digitsOnly`
(ASCII `0-9` only), `maxLength` 6 with the counter hidden, numeric keyboard,
`AutofillHints.oneTimeCode` (the OS can offer the code from the email or SMS) and
[`ClearsErrorOnEdit`](#design-widgets) like the other fields. It has no logic: the rule "exactly 6
ASCII digits" is `validateCode` (full-width and other Unicode digits are refused, like the API), and
the typed text is never trimmed or rewritten. `ResendCodeButton` is described under
[ResendCooldown](#resendcooldown).

**PT:** O `CodeField` (em `core/design/widgets/`) é o campo de 6 dígitos:
`FilteringTextInputFormatter.digitsOnly` (só `0-9` ASCII), `maxLength` 6 com o contador escondido,
teclado numérico, `AutofillHints.oneTimeCode` (o sistema pode oferecer o código do email ou SMS) e
[`ClearsErrorOnEdit`](#design-widgets) como os outros campos. Não tem lógica: a regra "exatamente 6
dígitos ASCII" é o `validateCode` (dígitos full-width e outros Unicode são recusados, como na API), e
o texto digitado nunca é aparado nem reescrito. O `ResendCodeButton` está descrito em
[ResendCooldown](#resendcooldown).
