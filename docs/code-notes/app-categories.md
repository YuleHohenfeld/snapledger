# Code notes: app categories

The long explanations behind the Flutter app's category management screen
(`app/lib/features/categories/`, opened from Profile > Categories). The code keeps one short line and
links here. The data comes from the contract's [Categories](../api-contract.md#categories) section; the
layers are in [ADR 0010](../decisions/0010-app-architecture-mvvmc-provider.md); the API side is in
[`category.md`](category.md).

**PT:** As explicações longas por trás da tela de gestão de categorias do app Flutter
(`app/lib/features/categories/`, aberta em Perfil > Categorias). O código mantém uma linha curta e
aponta para cá. Os dados vêm da seção [Categories](../api-contract.md#categories) do contrato; as camadas
estão no [ADR 0010](../decisions/0010-app-architecture-mvvmc-provider.md); o lado da API está em
[`category.md`](category.md).

## CategoryModel

The contract's `CategoryResponse`: `id`, `name`, `isDefault` and `key`. A **default** category is shared by
every user and read-only; its `key` is a stable lowercase code (`groceries`) and its `name` is the English
text. An **own** category has `key: null` and the user's own text as `name`.

Why a `key`: the default names would otherwise be fixed in English forever. With the key the app translates
the default from its own `.arb` files (`categoryDefaultGroceries`...), so adding `app_pt.arb` later changes no
API, no data and no model. `fromJson` is strict: a missing `id`, an empty `name`, a non-boolean `isDefault`,
or a **missing** `key` field throws `FormatException` (the contract says `key` is always present, so its
absence is a contract break that must fail loudly, not silently look like "own category"). `toString()` shows
only the id and `isDefault`: an own name is personal data and must not reach a log. `CategoryRequest` is
`{ "name": ... }` for both create and rename, and its `toString` masks the name too.

**PT:** O `CategoryResponse` do contrato: `id`, `name`, `isDefault` e `key`. Uma categoria **padrão** é
compartilhada por todos os usuários e somente leitura; a `key` é um código estável em minúsculas
(`groceries`) e o `name` é o texto em inglês. Uma categoria **própria** tem `key: null` e o texto do próprio
usuário como `name`.

**PT:** Por que uma `key`: sem ela os nomes das padrões ficariam fixos em inglês para sempre. Com a key o app
traduz a padrão pelos próprios `.arb` (`categoryDefaultGroceries`...), então adicionar o `app_pt.arb` depois
não muda API, dados nem modelo. O `fromJson` é estrito: `id` ausente, `name` vazio, `isDefault` não booleano
ou o campo `key` **ausente** lança `FormatException` (o contrato diz que a `key` sempre vem, então a ausência
é quebra de contrato que deve falhar alto, não parecer em silêncio uma "categoria própria"). O `toString()`
mostra só o id e `isDefault`: um nome próprio é dado pessoal e não pode ir para um log. O `CategoryRequest` é
`{ "name": ... }` para criar e renomear, e o `toString` dele também mascara o nome.

## CategoryRepository

`CategoryRepository` is the interface the ViewModel sees; `ApiCategoryRepository` implements it over the
`ApiClient` with the contract's paths: `GET /categories`, `POST /categories`, `PATCH /categories/{id}`
(rename), `DELETE /categories/{id}` (`204`). The id is encoded as one path segment
(`Uri.encodeComponent`), so an id with `/` can never reach another endpoint. A `2xx` body that breaks the
contract becomes a `ProblemFailure`, like in `UserRepository`, so the ViewModel handles one failure type. The
403/404/409 answers arrive as typed `ProblemFailure` (`defaultCategoryReadOnly`, `notFound`,
`categoryNameTaken`, `categoryInUse`) from the `ApiClient`.

**PT:** `CategoryRepository` é a interface que o ViewModel enxerga; `ApiCategoryRepository` a implementa
sobre o `ApiClient` com os caminhos do contrato: `GET /categories`, `POST /categories`,
`PATCH /categories/{id}` (renomear), `DELETE /categories/{id}` (`204`). O id é codificado como um só
segmento de caminho (`Uri.encodeComponent`), então um id com `/` nunca alcança outro endpoint. Um corpo
`2xx` que quebra o contrato vira `ProblemFailure`, como no `UserRepository`. As respostas 403/404/409 chegam
como `ProblemFailure` tipado vindo do `ApiClient`.

## validateCategoryName

Mirrors the contract for fast feedback (the API stays the authority): trimmed, 1-40 code points (an emoji
counts as one), and no control, format or lone-surrogate characters (the same `\p{Cc}\p{Cf}\p{Cs}` rule as the
register name and the API's `NoControlCharacters`). It lives in `categories/_shared/validation/` because the
expense form (next step) creates categories inline with the same rule. It returns an enum
(`CategoryNameError`) that the View turns into text, so the validator needs no l10n.

**PT:** Espelha o contrato para feedback rápido (a API continua sendo a autoridade): aparado, 1-40 code
points (um emoji conta como um) e sem caracteres de controle, de formatação ou surrogate solto (a mesma regra
`\p{Cc}\p{Cf}\p{Cs}` do nome do cadastro e do `NoControlCharacters` da API). Fica em
`categories/_shared/validation/` porque o formulário de gasto (próximo passo) cria categorias inline com a
mesma regra. Devolve um enum (`CategoryNameError`) que a View transforma em texto, então o validador não
precisa de l10n.

## categoryDisplayName

A View helper (`_shared/presentation/category_text.dart`): a default is shown translated from its `key`; an
own category shows its `name` exactly as typed, **even if it looks like a key** (an own category called `food`
stays `food`); a default with a key this app version does not know shows the `name` the API sent (a new default
added by a newer API still appears, in English). Both the manage screen and, later, the expense list and form use
it, so a category is spelled the same everywhere.

**PT:** Um helper da View (`_shared/presentation/category_text.dart`): uma padrão aparece traduzida pela `key`;
uma própria mostra o `name` exatamente como digitado, **mesmo que pareça uma key** (uma própria chamada `food`
continua `food`); uma padrão com uma key que esta versão do app não conhece mostra o `name` que a API mandou
(uma padrão nova de uma API mais nova ainda aparece, em inglês). A tela de gestão e, depois, a lista e o
formulário de gastos o usam, então uma categoria é escrita igual em todo lugar.

## CategoryManageViewModel

State is sealed: `Loading`, `Loaded(defaults, own, busy, failure)`, `Failed(failure)`. The failure inside
`Loaded` is kept **typed** (an `ApiFailure`, never a string) and the lists stay on screen, so a `409
category-in-use` while deleting does not blank the screen; the View localizes it.

- **One write at a time.** `create`, `rename` and `delete` go through `_write`, which returns false when the
  state is not `Loaded` or `busy` is already true. That is the double-submit guard (the same idea as the auth
  screens' `Submitting` state): a double tap or two open dialogs cannot send two requests. A refresh also sets
  `busy`, so a write never starts from a list that is about to be replaced.
- **Local update instead of a reload.** After a successful write the lists are updated locally, with the same
  order as the server (own categories by name without case, then id). It saves a request and avoids a flash; the
  pull-to-refresh is the way back to the server's truth (a `404` says so).
- **Stale list (`404`).** When a write fails with `not-found` (another device deleted the category), the
  failure is emitted and then `refresh()` reloads the list; the message stays next to the fresh list.
- **Sort caveat.** The local sort uses Dart `toLowerCase`, which may differ from the server collation for
  accented names until the next refresh.
- **Own before defaults.** The manage screen lists own categories first; the picker (step 4) is still to be decided.
- **Rename without a change** (`Pets` -> `Pets`) succeeds without a request; changing only the letter case is
  sent (the contract allows it).
- **A new attempt starts from a clean state**: `_write` clears the previous failure before the request, so a
  success never keeps an old error on screen (a test covers it).
- **Dispose guard.** `_emit` ignores everything after `dispose()`: an answer that arrives after the user left
  the screen must not notify a disposed notifier.

**PT:** O estado é selado: `Loading`, `Loaded(defaults, own, busy, failure)`, `Failed(failure)`. A falha dentro
do `Loaded` é mantida **tipada** (um `ApiFailure`, nunca uma string) e as listas continuam na tela, então um
`409 category-in-use` ao apagar não deixa a tela em branco; a View a traduz.

**PT:** Uma escrita por vez: `create`, `rename` e `delete` passam por `_write`, que devolve falso quando o
estado não é `Loaded` ou o `busy` já é verdadeiro. Essa é a trava de envio duplicado (a mesma ideia do estado
`Submitting` das telas de auth): um toque duplo ou dois diálogos abertos não enviam duas requisições. Um refresh
também liga o `busy`, então uma escrita nunca parte de uma lista que está prestes a ser trocada. Depois de uma
escrita com sucesso as listas são atualizadas localmente, na mesma ordem do servidor (próprias por nome sem
diferenciar caixa, depois id): economiza uma requisição e evita um piscar; o puxar para atualizar é o caminho de
volta à verdade do servidor (um `404` avisa isso). Renomear sem mudança (`Pets` -> `Pets`) tem sucesso sem
requisição; mudar só a caixa é enviado (o contrato permite). Uma nova tentativa parte de um estado limpo: o
`_write` limpa a falha anterior antes da requisição, então um sucesso nunca mantém um erro antigo na tela (há um
teste). O `_emit` ignora tudo depois do `dispose()`. Num `404` (outro aparelho apagou a categoria) a falha é
emitida e depois o `refresh()` recarrega a lista, mantendo a mensagem. A ordenação local usa o `toLowerCase`
do Dart e pode diferir da collation do servidor para acentos até o próximo refresh. A tela de gerenciar lista as
próprias antes das padrão; o seletor (passo 4) ainda será decidido.

## CategoryManageController

Owns the screen-only state of the name dialog: the `TextEditingController`, the `FocusNode`, the form key and
**which category is being renamed** (null while creating). `beginCreate()` / `beginRename(category)` prepare the
dialog and drop an old failure; `onSaveName()` validates (showing the field error) and then calls the ViewModel,
returning true only when the save worked, which tells the dialog to close. A server failure (for example `409
name taken`) returns false: the dialog stays open with the typed text, and the error disappears as soon as the user
edits the name (`onNameEdited` clears it in the ViewModel). `onDialogClosed()` clears a failure left by a cancelled
attempt, so it does not reappear as a banner on the page. The controller is created in `State.initState` and
released in `State.dispose`.

**PT:** Guarda o estado só da tela do diálogo de nome: o `TextEditingController`, o `FocusNode`, a form key e
**qual categoria está sendo renomeada** (nulo ao criar). `beginCreate()` / `beginRename(category)` preparam o
diálogo e descartam uma falha antiga; `onSaveName()` valida (mostrando o erro do campo) e depois chama o
ViewModel, devolvendo true só quando o salvar deu certo, o que diz ao diálogo para fechar. Uma falha do servidor
(por exemplo `409 nome em uso`) devolve false: o diálogo continua aberto com o texto digitado, e o erro some assim
que o usuário edita o nome (`onNameEdited` o limpa no ViewModel). O `onDialogClosed()` limpa uma falha deixada por
uma tentativa cancelada, para ela não reaparecer como banner na página. O controller é criado no
`State.initState` e liberado no `State.dispose`.

## CategoryManagePage

Profile > Categories (`/profile/categories`, a sub-route of the profile tab, opened with `push`). Own categories
come first (they are what the user acts on; the eight defaults would push them off screen), then the defaults. A
default row shows a **lock icon** and one semantics label ("Groceries, default category, cannot be changed"); an
own row has a three-dots menu (rename, delete) whose tooltip names the category. Delete asks for confirmation
first. The `RefreshIndicator` calls the Controller's `onRefresh`.

Two dialog details worth knowing:

- A dialog opened with `showDialog` lives in the **root overlay**, outside the page's `Provider`. The page hands it
  the same ViewModel with `ChangeNotifierProvider.value` (an existing object, not one created in `build`, so the
  rule "never `.value` with an object created in build" is respected).
- The dialogs close themselves with `Navigator.of(context).pop()`. A dialog is a local overlay of the page, not an
  app location, so it is not an `AppNavigator` intent (those are for `AppRoute`s); the decision to close comes from
  the Controller's result (`onSaveName` true), not from the View.

**PT:** Perfil > Categorias (`/profile/categories`, uma sub-rota da aba de perfil, aberta com `push`). As
categorias próprias vêm primeiro (são o que o usuário manipula; as oito padrões as empurrariam para fora da
tela), depois as padrões. Uma linha padrão mostra um **ícone de cadeado** e um rótulo de semântica ("Groceries,
categoria padrão, não pode ser alterada"); uma linha própria tem um menu de três pontos (renomear, apagar) cujo
tooltip cita a categoria. Apagar pede confirmação antes. O `RefreshIndicator` chama o `onRefresh` do Controller.

**PT:** Dois detalhes dos diálogos: um diálogo aberto com `showDialog` vive no **overlay raiz**, fora do `Provider`
da página; a página entrega a ele o mesmo ViewModel com `ChangeNotifierProvider.value` (um objeto existente, não
criado no `build`, então a regra "nunca `.value` com objeto criado no build" é respeitada). E os diálogos se
fecham com `Navigator.of(context).pop()`: um diálogo é uma camada local da página, não um endereço do app (as
intenções do `AppNavigator` são para `AppRoute`s); a decisão de fechar vem do resultado do Controller
(`onSaveName` true), não da View.
