# Code notes: app profile

The long explanations behind the Flutter app's profile screen (`app/lib/features/profile/`). The
code keeps one short line and links here. The data comes from `GET /users/me` in the contract's
[Users](../api-contract.md#get-usersme) section; the session it signs out of is in
[`app-core.md`](app-core.md#sessionnotifier); the layers are in
[ADR 0010](../decisions/0010-app-architecture-mvvmc-provider.md).

**PT:** As explicações longas por trás da tela de perfil do app Flutter (`app/lib/features/profile/`).
O código mantém uma linha curta e aponta para cá. Os dados vêm do `GET /users/me` na seção
[Users](../api-contract.md#get-usersme) do contrato; a sessão da qual ele sai está no
[`app-core.md`](app-core.md#sessionnotifier); as camadas estão no
[ADR 0010](../decisions/0010-app-architecture-mvvmc-provider.md).

## UserRepository

`UserRepository` is the interface the ViewModel sees; `ApiUserRepository` implements it over the
`ApiClient` with the contract's path (`GET /users/me`). It is the only layer that talks to the API.
A `2xx` body that breaks the contract (`UserModel.fromJson` throws `FormatException`) becomes a
`ProblemFailure`, so the ViewModel handles a single failure type. A `401` never reaches it as a
final answer when a refresh can fix it: the `AuthInterceptor` refreshes and retries once, and wipes
the session when it cannot (the router then opens the login). Changing name or currency waits for
`PATCH /users/me`, so there is no method for it yet (it is on the roadmap).

**PT:** `UserRepository` é a interface que o ViewModel enxerga; `ApiUserRepository` a implementa
sobre o `ApiClient` com o caminho do contrato (`GET /users/me`). É a única camada que fala com a
API. Um corpo `2xx` que quebra o contrato (o `UserModel.fromJson` lança `FormatException`) vira um
`ProblemFailure`, então o ViewModel trata um só tipo de falha. Um `401` não chega a ele como
resposta final quando um refresh resolve: o `AuthInterceptor` renova e repete uma vez, e apaga a
sessão quando não consegue (o router então abre o login). Trocar nome ou moeda espera o
`PATCH /users/me`, então ainda não há método para isso (está no roadmap).

## ProfileViewModel

State is `ProfileLoading` (initial), `ProfileLoaded(user)` or `ProfileFailed(failure)`; the View
localizes the failure with `failureMessage` and offers a retry that calls `load()` again.
`load()` does not notify when it is already loading, because the Controller calls it from
`initState`.

`logout()` calls `session.signOut(revoke: authRepository.logout)`: the server session is revoked
best effort with a 5 s timeout, and the local tokens are wiped **whatever happens** (offline, a
server error, a keychain error). The user must always be able to leave. After the wipe the status
becomes signed out and the router sends the user to login; the ViewModel navigates nowhere. While it
runs, `loggingOut` is true (the button is disabled and shows a spinner) and a second tap or a
`load()` is ignored.

**PT:** O estado é `ProfileLoading` (inicial), `ProfileLoaded(user)` ou `ProfileFailed(failure)`; a
View traduz a falha com o `failureMessage` e oferece um tentar de novo que chama `load()` outra vez.
O `load()` não notifica quando já está carregando, porque o Controller o chama no `initState`.

**PT:** O `logout()` chama `session.signOut(revoke: authRepository.logout)`: a sessão do servidor é
revogada com melhor esforço e timeout de 5 s, e os tokens locais são apagados **aconteça o que
acontecer** (offline, erro do servidor, erro do keychain). O usuário precisa sempre poder sair.
Depois do wipe o status vira deslogado e o router manda para o login; o ViewModel não navega para
lugar nenhum. Enquanto roda, `loggingOut` é verdadeiro (o botão fica desativado com um spinner) e
um segundo toque ou um `load()` são ignorados.
