# Code notes: app expenses

The long explanations behind the Flutter app's Expenses tab and expense form
(`app/lib/features/expenses/`). The code keeps one short line and links here. The data comes from the
contract's [Expenses](../api-contract.md#expenses) section; money and dates follow
[ADR 0015](../decisions/0015-money-and-calendar-dates.md); the layers are in
[ADR 0010](../decisions/0010-app-architecture-mvvmc-provider.md); the API side is in
[`expense.md`](expense.md). Categories are in [`app-categories.md`](app-categories.md).

**PT:** As explicações longas por trás da aba Despesas e do formulário de gasto do app Flutter
(`app/lib/features/expenses/`). O código mantém uma linha curta e aponta para cá. Os dados vêm da seção
[Expenses](../api-contract.md#expenses) do contrato; dinheiro e datas seguem o
[ADR 0015](../decisions/0015-money-and-calendar-dates.md); as camadas estão no
[ADR 0010](../decisions/0010-app-architecture-mvvmc-provider.md); o lado da API está em
[`expense.md`](expense.md). As categorias estão em [`app-categories.md`](app-categories.md).

## ExpenseModel

`ExpenseModel` is the contract's `ExpenseResponse`. The `amount` arrives as a **string** (`"42.90"`) and is read with
`Decimal.parse`, never through a `double`; before parsing, `fromJson` checks the contract's own pattern
(`^(0|[1-9][0-9]{0,9})(\.[0-9]{1,2})?$`), so `"1e3"`, `"-1"` or three decimals fail loudly instead of becoming a
number nobody asked for. The `date` is a calendar day (`yyyy-MM-dd`): it is read by `parseCalendarDate` into local
midnight of that day, and a day that does not exist (`2026-02-30`) is **refused**, not rolled over to March. The `id`
must be a UUID (like `CategoryModel`): it is later put in a URL path, so a malformed id is a contract break that
must fail at the edge. Every `FormatException` names the field, never the value, and `toString` shows only the id
(amount and description are personal data).

`ExpenseRequest` is the body of `POST` and `PUT`: the amount is written with `toStringAsFixed(2)` (`"1500.00"` for a
whole number: the contract accepts 1 or 2 places and the app always sends 2), the date with `formatCalendarDate`, and
a `PUT` replaces the whole expense, so every field is always sent.

**PT:** O `ExpenseModel` é o `ExpenseResponse` do contrato. O `amount` chega como **string** (`"42.90"`) e é lido com
`Decimal.parse`, nunca por um `double`; antes de ler, o `fromJson` confere o padrão do próprio contrato
(`^(0|[1-9][0-9]{0,9})(\.[0-9]{1,2})?$`), então `"1e3"`, `"-1"` ou três casas falham alto em vez de virar um
número que ninguém pediu. A `date` é um dia de calendário (`yyyy-MM-dd`): é lida pelo `parseCalendarDate` como
meia-noite local desse dia, e um dia que não existe (`2026-02-30`) é **recusado**, não deslocado para março. O `id`
precisa ser um UUID (como no `CategoryModel`): ele vai depois num caminho de URL, então um id malformado é quebra de
contrato e deve falhar na borda. Todo `FormatException` cita o campo, nunca o valor, e o `toString` mostra só o id
(valor e descrição são dados pessoais).

O `ExpenseRequest` é o corpo de `POST` e `PUT`: o valor é escrito com `toStringAsFixed(2)` (`"1500.00"` para um
inteiro: o contrato aceita 1 ou 2 casas e o app sempre manda 2), a data com `formatCalendarDate`, e um `PUT`
substitui o gasto inteiro, então todo campo é sempre enviado.

## ExpenseRepository

`ExpenseRepository` is the interface the ViewModels see; `ApiExpenseRepository` implements it over the `ApiClient`:
`GET /expenses?month=YYYY-MM[&categoryId=]` (the filter is sent only when given), `GET`, `POST`, `PUT` and `DELETE
/expenses/{id}` (the id is encoded as one path segment with `Uri.encodeComponent`, so an id with `/` cannot reach
another endpoint). A `2xx` body that breaks the contract becomes a `ProblemFailure`, like the other repositories.

**`changes`** is a `Listenable` that fires after every write the server accepted (`create`, `update`, `delete`) and
never after a read or a failed write. Why: the list and the form are different screens with different ViewModels;
the form must not know the list exists, and the list must not need a manual refresh. The list ViewModel listens to
`changes` and reloads; any future screen (the summary) can listen too. It fires as soon as the server answered
`2xx`, **before** the body is parsed: if the body is unreadable the write still happened, so open lists must
reload. The repository owns the notifier and releases it through `dispose()` (the `Provider` calls it).

**PT:** O `ExpenseRepository` é a interface que os ViewModels enxergam; o `ApiExpenseRepository` a implementa sobre o
`ApiClient`: `GET /expenses?month=YYYY-MM[&categoryId=]` (o filtro só vai quando informado), `GET`, `POST`, `PUT` e
`DELETE /expenses/{id}` (o id é codificado como um só segmento de caminho com `Uri.encodeComponent`, então um id
com `/` não alcança outro endpoint). Um corpo `2xx` que quebra o contrato vira `ProblemFailure`, como nos outros
repositórios.

**`changes`** é um `Listenable` que dispara depois de toda escrita que o servidor aceitou (`create`, `update`,
`delete`) e nunca depois de uma leitura ou de uma escrita que falhou. Por quê: a lista e o formulário são telas
diferentes com ViewModels diferentes; o formulário não deve saber que a lista existe, e a lista não deve precisar de
atualização manual. O ViewModel da lista escuta o `changes` e recarrega; qualquer tela futura (o resumo) pode
escutar também. Dispara assim que o servidor respondeu `2xx`, **antes** de ler o corpo: se o corpo for ilegível a
escrita aconteceu mesmo assim, então as listas abertas precisam recarregar. O repositório é dono do notifier e o
libera pelo `dispose()` (o `Provider` o chama).

## validators

Same idea as `validateCategoryName`: fast feedback on the device, the API stays the authority.

- **Amount** (`validateExpenseAmount`): empty is `required`; `parseMoneyInput` (locale separators, at most the
  currency's decimals, never a guess) turns the text into a `Decimal`, otherwise `invalid`; zero is `notPositive`;
  above `9999999999.99` is `tooLarge`. The text is parsed with the **user's locale**, so `42,90` is right in pt_BR and
  `42.90` there is refused as ambiguous.
- **Description** (`validateExpenseDescription`): ends trimmed, 1 to 120 **code points** (an emoji is one, like the API),
  no control (Cc), format (Cf) or lone surrogate (Cs) code points.
- **Date** (`validateExpenseDate`): from `2000-01-01` up to **today plus one day**, where "today" is the device's
  local day and `now` is injected (tests need no clock). The extra day mirrors the API, which allows today's UTC date
  plus one so a phone ahead of UTC can record "today" (ADR 0015, rule 7). `latestExpenseDate` also feeds the date picker's
  `lastDate`, so the picker cannot offer a day the API would refuse.

**PT:** A mesma ideia do `validateCategoryName`: retorno rápido no aparelho, a API continua sendo a autoridade.

- **Valor** (`validateExpenseAmount`): vazio é `required`; o `parseMoneyInput` (separadores do locale, no máximo as
  casas da moeda, nunca um palpite) transforma o texto num `Decimal`, senão `invalid`; zero é `notPositive`; acima de
  `9999999999.99` é `tooLarge`. O texto é lido com o **locale do usuário**, então `42,90` está certo em pt_BR e
  `42.90` lá é recusado como ambíguo.
- **Descrição** (`validateExpenseDescription`): pontas aparadas, de 1 a 120 **code points** (um emoji é um, como na
  API), sem code points de controle (Cc), formatação (Cf) ou surrogate sozinho (Cs).
- **Data** (`validateExpenseDate`): de `2000-01-01` até **hoje mais um dia**, onde "hoje" é o dia local do aparelho e
  o `now` é injetado (os testes não precisam de relógio). O dia extra espelha a API, que permite a data UTC de hoje
  mais um para um celular à frente do UTC poder registrar "hoje" (ADR 0015, regra 7). O `latestExpenseDate` também
  alimenta o `lastDate` do seletor de data, que então não oferece um dia que a API recusaria.

## ExpenseListViewModel

State is sealed: `Loading(month)`, `Loaded(month, currency, days, monthTotal, failure?)` and `Failed(month, failure)`;
every state carries the month so the selector always shows it. An empty month is `Loaded` with no days.

- **Parallel load.** The month's expenses and the user's currency (`UserRepository.fetchCurrent`) are requested together
  with `Future.wait`; it waits for both even when one fails, so no second error escapes unhandled. The currency is
  asked once per screen and kept (it cannot change inside the app yet).
- **Grouping and totals.** Expenses are grouped by calendar day in the server's order (newest day first). Each group
  has an exact `Decimal` total and the month total is the sum of **all expenses**, which is equal to the sum of the
  day totals (a test checks `0.10 + 0.20` style sums to the cent). The group also carries `ExpenseDayKind`
  (`today`, `yesterday`, `other`) computed from the injected `now`, so the View writes "Today" or "Yesterday" without
  any date logic.
- **Month navigation.** `showPreviousMonth` / `showNextMonth`; `canGoNext` is false in the current month, because an
  expense cannot be dated further than tomorrow. A **ticket** number is bumped on every load: an answer for a month the
  user already left is dropped, so a slow response never overwrites the month on screen.
- **Refresh and `changes`.** Pull to refresh and a write from the form call `refresh()`: the list stays on screen and is
  swapped when the answer arrives; a failure is kept in `Loaded.failure` next to the old list. The ViewModel listens
  to `ExpenseRepository.changes` and removes the listener in `dispose()`, which also guards `notifyListeners`.

**PT:** O estado é selado: `Loading(month)`, `Loaded(month, currency, days, monthTotal, failure?)` e
`Failed(month, failure)`; todo estado leva o mês para o seletor sempre mostrá-lo. Um mês vazio é `Loaded` sem dias.

- **Carga em paralelo.** Os gastos do mês e a moeda do usuário (`UserRepository.fetchCurrent`) são pedidos juntos com
  `Future.wait`; ele espera os dois mesmo quando um falha, então nenhum segundo erro escapa sem tratamento. A moeda
  é pedida uma vez por tela e guardada (ela ainda não muda dentro do app).
- **Agrupamento e totais.** Os gastos são agrupados por dia de calendário na ordem do servidor (dia mais novo
  primeiro). Cada grupo tem um total `Decimal` exato e o total do mês é a soma de **todos os gastos**, igual à soma
  dos totais dos dias (um teste confere somas do tipo `0.10 + 0.20` até o centavo). O grupo também leva o
  `ExpenseDayKind` (`today`, `yesterday`, `other`) calculado do `now` injetado, para a View escrever "Hoje" ou
  "Ontem" sem lógica de data.
- **Navegação de mês.** `showPreviousMonth` / `showNextMonth`; o `canGoNext` é falso no mês atual, porque um gasto não
  pode ter data além de amanhã. Um número de **ticket** sobe a cada carga: a resposta de um mês que o usuário já
  deixou é descartada, então uma resposta lenta nunca sobrescreve o mês na tela.
- **Atualizar e `changes`.** Puxar para atualizar e uma escrita do formulário chamam `refresh()`: a lista fica na
  tela e é trocada quando a resposta chega; uma falha fica em `Loaded.failure` junto da lista antiga. O ViewModel
  escuta o `ExpenseRepository.changes` e remove o listener no `dispose()`, que também protege o `notifyListeners`.

## ExpenseListController

No screen-only state exists on the list, so the Controller only forwards events: retry, previous / next month and
pull to refresh go to the ViewModel; "add" pushes `AppRoute.expenseNew` and a tap on a row calls
`AppNavigator.pushExpenseEdit(id)`. It does **not** await the pushed screen: the list reloads itself through
`ExpenseRepository.changes` when the form saves, which is also correct when the write comes from somewhere else.

**PT:** A lista não tem estado só de tela, então o Controller apenas encaminha eventos: tentar de novo, mês
anterior / seguinte e puxar para atualizar vão ao ViewModel; "adicionar" empilha `AppRoute.expenseNew` e o toque numa
linha chama `AppNavigator.pushExpenseEdit(id)`. Ele **não** espera a tela empilhada: a lista recarrega sozinha pelo
`ExpenseRepository.changes` quando o formulário salva, o que também vale quando a escrita vem de outro lugar.

## ExpenseListPage

`ExpenseListPage` replaces the old placeholder: `MonthSelector`, then, by state, a spinner, `ExpenseLoadError`
(message + retry) or `ExpenseListContent`: a gradient `MonthTotalCard` (white on the deep blue, WCAG AA), day headers
with the day total, `ExpenseTile` rows (description, the category as a `PillChip`, amount) and, for an empty month, the
`EmptyState` with its `GlowOrb`. The scroll view is always scrollable so pull to refresh also works on an empty month.
All money goes through `formatMoney` (never a `double`, never hides a cent). A floating "Add expense" button opens the
form. The page takes a `now` function (default `DateTime.now`) so tests fix "Today". A month is a bounded window, so
the list is not paginated (the contract says to revisit above ~1,000 items).

**PT:** A `ExpenseListPage` substitui o marcador antigo: `MonthSelector` e, conforme o estado, um spinner,
`ExpenseLoadError` (mensagem + tentar de novo) ou `ExpenseListContent`: um `MonthTotalCard` com gradiente (branco no
azul escuro, WCAG AA), cabeçalhos de dia com o total do dia, linhas `ExpenseTile` (descrição, a categoria como
`PillChip`, valor) e, para um mês vazio, o `EmptyState` com seu `GlowOrb`. A rolagem é sempre ativa para o puxar
para atualizar funcionar também num mês vazio. Todo dinheiro passa pelo `formatMoney` (nunca um `double`, nunca
esconde um centavo). Um botão flutuante "Add expense" abre o formulário. A página recebe uma função `now` (padrão
`DateTime.now`) para os testes fixarem o "Hoje". Um mês é uma janela limitada, então a lista não tem paginação (o
contrato diz para rever acima de ~1.000 itens).

## ExpenseFormViewModel

One ViewModel for create (`expenseId == null`) and edit. State: `Loading`, `NotFound`, `Failed(failure)`,
`Editing(categories, currency, initial?, saving, creatingCategory, failure?, categoryFailure?)`, `Saved(form)` and
`Deleted(form)` (the last two keep the form as it was, still busy, so the screen does not flash while the route closes).

- **Load.** Categories, the user's currency and, when editing, the expense **by id** are requested in parallel, so a
  deep link to `/expenses/:id` works with no list in memory. When editing, a `404 not-found` **or** a
  `400 validation-error` (a malformed id) becomes `NotFound`: for the user both mean "that expense does not exist".
  In create mode a 404 is just a failure (there is nothing to find). Any other failure is `Failed` with a retry.
- **Save.** `save(ExpenseRequest)` creates or replaces (`PUT`). The `saving` flag is set **before** the first `await`, so a
  double tap finds it on and does nothing (one request). A failure keeps the form, with the typed `ApiFailure`
  so the View maps `400` field names to the matching fields (`amount`, `description`, `date`, `categoryId`).
- **Field errors.** `clearFieldError(field)` removes only that field from the failure, keeps the others and, when none
  is left, removes the failure; a form-level failure (network) goes away on any edit. This follows the rule "a
  field's error disappears as soon as the user edits that field" more precisely than clearing everything.
- **Delete.** Only when editing; a `404` while deleting shows `NotFound` (it is already gone).
- **Inline category.** `createCategory(name)` goes through `CategoryRepository` (a feature may use another's `_shared/data`),
  keeps its own failure (`categoryFailure`, for example `409 category-name-taken`) apart from the expense failure
  and returns the new category, already in the list.

**PT:** Um ViewModel para criar (`expenseId == null`) e editar. Estado: `Loading`, `NotFound`, `Failed(failure)`,
`Editing(categories, currency, initial?, saving, creatingCategory, failure?, categoryFailure?)`, `Saved(form)` e
`Deleted(form)` (os dois últimos guardam o formulário como estava, ainda ocupado, para a tela não piscar enquanto a
rota fecha).

- **Carga.** Categorias, a moeda do usuário e, ao editar, o gasto **pelo id** são pedidos em paralelo, então um
  deep link para `/expenses/:id` funciona sem nenhuma lista na memória. Ao editar, um `404 not-found` **ou** um
  `400 validation-error` (id malformado) vira `NotFound`: para o usuário os dois significam "esse gasto não existe".
  No modo criar um 404 é só uma falha (não há o que achar). Qualquer outra falha é `Failed` com tentar de novo.
- **Salvar.** `save(ExpenseRequest)` cria ou substitui (`PUT`). A flag `saving` é ligada **antes** do primeiro
  `await`, então um toque duplo a encontra ligada e nada faz (uma requisição). Uma falha mantém o formulário, com
  o `ApiFailure` tipado para a View mapear os nomes de campo do `400` nos campos certos (`amount`, `description`,
  `date`, `categoryId`).
- **Erros de campo.** `clearFieldError(field)` remove só aquele campo da falha, mantém os outros e, quando não sobra
  nenhum, remove a falha; uma falha do formulário (rede) some em qualquer edição. Isso segue a regra "o erro de um
  campo some assim que o usuário edita aquele campo" com mais precisão do que limpar tudo.
- **Apagar.** Só ao editar; um `404` ao apagar mostra `NotFound` (já não existe).
- **Categoria embutida.** `createCategory(name)` passa pelo `CategoryRepository` (uma feature pode usar o `_shared/data`
  de outra), guarda a própria falha (`categoryFailure`, por exemplo `409 category-name-taken`) separada da falha do
  gasto e devolve a nova categoria, já na lista.

## ExpenseFormController

Holds the screen-only state: the amount and description `TextEditingController`s and focus nodes, the chosen **date**
and **category** (`ValueNotifier`s the View listens to), the device-side errors of those two fields and the "New
category" field of the sheet. Everything is released in `dispose()` (which is idempotent).

- **Filling.** It listens to the ViewModel and, **once**, when the form data arrives, fills the fields: the loaded
  expense's values (the amount through `moneyInputText`, which writes the locale's separator), or today for a new one. It
  never overwrites what the user typed afterwards.
- **Locale.** The Controller needs the locale to read and write the amount, and `Localizations.localeOf` cannot be read in
  `initState`. So the page creates it in `didChangeDependencies` (once). This is the one place where the "create in
  `initState`" rule bends, for a concrete reason.
- **Submit.** It runs the field validators (so the `Form` shows the messages) and also checks the date and category; with
  anything invalid it stops. Otherwise it builds the `ExpenseRequest` (`Decimal` from `parseMoneyInput`, the trimmed
  description, the day, the category id), calls `save` and, on success, `AppNavigator.pop()` (not if the screen was
  disposed meanwhile).
- **Preview.** `previewText` is the typed amount formatted with `formatMoney` for the user's currency ("Will be saved as
  R$ 42,90"), shown under the field while the amount is valid. It is the security review's recommendation: a misplaced
  separator is seen **before** saving, not after.
- **Date picker.** `pickerStart`, `firstDate` and `lastDate` come from here; the start is clamped into the range because
  `showDatePicker` asserts when it is outside it (a device that changed time zone could hold a date beyond `lastDate`).

**PT:** Guarda o estado só da tela: os `TextEditingController`s e focus nodes de valor e descrição, a **data** e a
**categoria** escolhidas (`ValueNotifier`s que a View escuta), os erros no aparelho desses dois campos e o campo
"Nova categoria" da folha. Tudo é liberado no `dispose()` (que é idempotente).

- **Preenchimento.** Ele escuta o ViewModel e, **uma vez**, quando os dados do formulário chegam, preenche os campos:
  os valores do gasto carregado (o valor pelo `moneyInputText`, que escreve o separador do locale), ou hoje num
  novo. Nunca sobrescreve o que o usuário digitou depois.
- **Locale.** O Controller precisa do locale para ler e escrever o valor, e o `Localizations.localeOf` não pode ser
  lido no `initState`. Então a página o cria no `didChangeDependencies` (uma vez). É o único lugar onde a regra "criar
  no `initState`" cede, por um motivo concreto.
- **Envio.** Roda os validators dos campos (para o `Form` mostrar as mensagens) e confere também a data e a
  categoria; com algo inválido, para. Senão monta o `ExpenseRequest` (`Decimal` do `parseMoneyInput`, a descrição
  aparada, o dia, o id da categoria), chama `save` e, no sucesso, `AppNavigator.pop()` (não se a tela foi descartada
  nesse meio tempo).
- **Prévia.** `previewText` é o valor digitado formatado com `formatMoney` na moeda do usuário ("Será salvo como
  R$ 42,90"), mostrado sob o campo enquanto o valor é válido. É a recomendação da revisão de segurança: um separador
  fora do lugar é visto **antes** de salvar, não depois.
- **Seletor de data.** `pickerStart`, `firstDate` e `lastDate` vêm daqui; o início é limitado ao intervalo porque o
  `showDatePicker` falha com assertion quando está fora dele (um aparelho que mudou de fuso poderia ter uma data
  além do `lastDate`).

## ExpenseFormPage

`ExpenseFormPage({expenseId})`: no id it is "New expense", with one it is "Edit expense" and shows a delete button in
the app bar. By state: spinner, `ExpenseNotFound` (an `EmptyState` with a "Back" button), `ExpenseLoadError` (retry) or
`ExpenseFormBody`: `MoneyField` (currency symbol, decimals of the currency), the `AmountPreview`, the description
`AppTextField`, `ExpenseDateField` (opens `showDatePicker` in the View and hands the result to the Controller),
`ExpenseCategoryField` (opens the picker sheet) and the `GradientButton`. Server field errors (`400`) show under the
matching field and go away when it is edited. **Delete** exists only on the edit screen, behind a confirmation dialog
(the contract says the delete is final, owner decision Q9); the dialog and the sheet are local overlays closed with
their own `Navigator.of(context).pop()`, which `app/CLAUDE.md` allows in the View.

**PT:** `ExpenseFormPage({expenseId})`: sem id é "New expense", com id é "Edit expense" e mostra um botão de apagar
na app bar. Por estado: spinner, `ExpenseNotFound` (um `EmptyState` com botão "Back"), `ExpenseLoadError` (tentar de
novo) ou `ExpenseFormBody`: `MoneyField` (símbolo da moeda, casas da moeda), o `AmountPreview`, o `AppTextField` da
descrição, `ExpenseDateField` (abre o `showDatePicker` na View e entrega o resultado ao Controller),
`ExpenseCategoryField` (abre a folha de categorias) e o `GradientButton`. Erros de campo do servidor (`400`) aparecem
sob o campo certo e somem quando ele é editado. **Apagar** existe só na tela de edição, atrás de um diálogo de
confirmação (o contrato diz que o apagar é definitivo, decisão do dono Q9); o diálogo e a folha são camadas locais
fechadas com o próprio `Navigator.of(context).pop()`, que o `app/CLAUDE.md` permite na View.

## CategoryPickerSheet

A modal bottom sheet that lists the categories and creates one on the spot (owner decision Q8). **Order:** the user's
**own** categories first (by name without case, then id), then the defaults in the server's order. This is the same
order as the Profile > Categories screen (own first, defaults after): the categories a person made are the ones they
reach for most, and the eight defaults are always there below. Defaults show their translated name (`categoryDisplayName`);
own ones show as written. The chosen one has a check. At the bottom, a "New category" field and an "Add" button create
the category through the ViewModel (`createCategory`), choose it and close the sheet; a refused name (taken, invalid)
stays in the sheet, under the field, and its error goes away when the name is edited. The sheet lives in the root
overlay, outside the page's `Provider`, so the page hands it the same ViewModel with `ChangeNotifierProvider.value`
(like the name dialog of the categories screen) and the Controller owns the field.

**PT:** Uma folha modal que lista as categorias e cria uma na hora (decisão do dono Q8). **Ordem:** as categorias
**próprias** do usuário primeiro (por nome sem diferenciar caixa, depois id), depois as padrão na ordem do servidor. É a
mesma ordem da tela Perfil > Categorias (próprias primeiro, padrão depois): as categorias que a pessoa criou são as
que ela mais usa, e as oito padrão estão sempre ali embaixo. As padrão mostram o nome traduzido
(`categoryDisplayName`); as próprias, como foram escritas. A escolhida tem um check. No fim, um campo "New category" e
um botão "Add" criam a categoria pelo ViewModel (`createCategory`), a escolhem e fecham a folha; um nome recusado
(repetido, inválido) fica na folha, sob o campo, e o erro some quando o nome é editado. A folha vive no overlay
raiz, fora do `Provider` da página, então a página entrega a ela o mesmo ViewModel com
`ChangeNotifierProvider.value` (como o diálogo de nome da tela de categorias) e o Controller é dono do campo.

## routes

`AppRoute.expenseNew` is `/expenses/new`; the edit screen is `/expenses/:id` (`AppRoute.expenseEditPattern`), and
`AppRoute.expenseEditPath(id)` builds a location with the id percent-encoded as one segment.
`AppNavigator.pushExpenseEdit(id)` is the intent (`GoRouterNavigator` pushes that location). Both are **sub-routes of
the Expenses route**, declared in `app_routes.dart` (`new` before `:id`, because `:id` would also match `new`), so
a deep link to `/expenses/<id>` still has the list below it and `pop()` always has somewhere to go.

**Session and deep links.** `redirectFor` treats `/expenses/new` and `/expenses/<id>` as tab paths: a signed-in user
stays, a signed-out user goes to `/login`. The `?from=` allowlist stays **exactly** `/summary`, `/expenses`, `/profile`,
so a deep link to an expense does **not** survive the login (the user lands on `/summary` after signing in). That is on
purpose: an allowlist that accepted a pattern (`/expenses/<anything>`) would be a wider surface for an open redirect, and
the expense form only reads ids that the API checks per user anyway. Widening it is a later, deliberate decision.

**PT:** `AppRoute.expenseNew` é `/expenses/new`; a tela de edição é `/expenses/:id` (`AppRoute.expenseEditPattern`), e
`AppRoute.expenseEditPath(id)` monta um endereço com o id codificado como um só segmento.
`AppNavigator.pushExpenseEdit(id)` é a intenção (o `GoRouterNavigator` empilha esse endereço). As duas são
**sub-rotas da rota Despesas**, declaradas em `app_routes.dart` (`new` antes de `:id`, porque `:id` também casaria
com `new`), então um deep link para `/expenses/<id>` ainda tem a lista embaixo e o `pop()` sempre tem para onde ir.

**Sessão e deep links.** O `redirectFor` trata `/expenses/new` e `/expenses/<id>` como caminhos de aba: um usuário
logado fica, um deslogado vai para `/login`. A allowlist do `?from=` continua **exatamente** `/summary`, `/expenses`,
`/profile`, então um deep link para um gasto **não** sobrevive ao login (o usuário cai em `/summary` depois de
entrar). É de propósito: uma allowlist que aceitasse um padrão (`/expenses/<qualquer coisa>`) seria uma superfície
maior para open redirect, e o formulário só lê ids que a API confere por usuário de qualquer forma. Ampliá-la é uma
decisão futura e deliberada.
