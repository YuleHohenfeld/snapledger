# Code notes: app summary

The long explanations behind the Flutter app's Summary tab (`app/lib/features/summary/`). The code keeps one short
line and links here. The data comes from the contract's
[`GET /expenses/summary`](../api-contract.md#get-expensessummarymonthyyyy-mm); money and dates follow
[ADR 0015](../decisions/0015-money-and-calendar-dates.md); the layers are in
[ADR 0010](../decisions/0010-app-architecture-mvvmc-provider.md); the API side is in [`expense.md`](expense.md).
The expense list this tab mirrors is in [`app-expenses.md`](app-expenses.md).

**PT:** As explicações longas por trás da aba Resumo do app Flutter (`app/lib/features/summary/`). O código mantém
uma linha curta e aponta para cá. Os dados vêm do
[`GET /expenses/summary`](../api-contract.md#get-expensessummarymonthyyyy-mm) do contrato; dinheiro e datas seguem
o [ADR 0015](../decisions/0015-money-and-calendar-dates.md); as camadas estão no
[ADR 0010](../decisions/0010-app-architecture-mvvmc-provider.md); o lado da API está em [`expense.md`](expense.md). A
lista de gastos que esta aba acompanha está em [`app-expenses.md`](app-expenses.md).

## ExpenseSummaryModel

`ExpenseSummaryModel` (and `CategorySummaryModel` for each `byCategory` row) reads the contract's JSON and validates
its shape, like the other models: a missing or malformed field throws a `FormatException` that names the field and
never the value (the totals are personal data; `toString` shows only the month or the category id). Money
(`total`, `previousMonthTotal`, each row's `total`) and `percentage` are **strings** in the contract and become
`Decimal` through `Decimal.parse` after a regex check; there is no digit limit on the totals (a month sums many
expenses), only "no sign, no exponent, at most 2 places". `percentage` must be 0 to 100. `categoryId` must be a UUID.
`byCategory` is copied into an unmodifiable list, in the server's order (biggest total first), which the chart keeps.

**PT:** O `ExpenseSummaryModel` (e o `CategorySummaryModel` para cada linha de `byCategory`) lê o JSON do contrato e
valida o formato, como os outros models: um campo ausente ou malformado lança uma `FormatException` que cita o campo
e nunca o valor (os totais são dados pessoais; o `toString` mostra só o mês ou o id da categoria). Dinheiro (`total`,
`previousMonthTotal`, o `total` de cada linha) e `percentage` são **strings** no contrato e viram `Decimal` com
`Decimal.parse` depois de uma checagem por regex; não há limite de dígitos nos totais (um mês soma muitos gastos),
só "sem sinal, sem expoente, no máximo 2 casas". `percentage` deve ir de 0 a 100. `categoryId` deve ser UUID.
O `byCategory` é copiado para uma lista imutável, na ordem do servidor (maior total primeiro), que o gráfico mantém.

## category names

`byCategory` rows carry `categoryName` but **no `key`**, so the app cannot translate a default category the way
`categoryDisplayName` does for the expense list. Decision: the Summary shows `categoryName` **as sent** (English for
a default, the user's own text for an own category). Not chosen: mapping the seeded default ids
(`c0000000-0000-4000-8000-00000000000N`) to keys in the app. Those ids exist only in a migration, not in the contract,
and a hard-coded table would break silently the day a default is added or renumbered. Proposed contract change (needs
the owner): add `categoryKey` (null for own categories) to each `byCategory` row, the same field `CategoryResponse`
already has; then the Summary can reuse `categoryDisplayName`. Until then the Summary and the Expenses list may show
different names for the same default category when the app is not in English.

**PT:** As linhas de `byCategory` trazem `categoryName` mas **nenhum `key`**, então o app não consegue traduzir uma
categoria padrão como o `categoryDisplayName` faz na lista de gastos. Decisão: o Resumo mostra o `categoryName`
**como veio** (inglês numa padrão, o texto do usuário numa própria). Não escolhido: mapear no app os ids fixos das
padrão (`c0000000-0000-4000-8000-00000000000N`) para keys. Esses ids existem só numa migration, não no contrato, e uma
tabela fixa no app quebraria em silêncio no dia em que uma padrão for adicionada ou renumerada. Mudança de contrato
proposta (precisa do dono): adicionar `categoryKey` (nulo nas próprias) a cada linha de `byCategory`, o mesmo campo
que o `CategoryResponse` já tem; aí o Resumo pode reusar o `categoryDisplayName`. Até lá o Resumo e a lista de gastos
podem mostrar nomes diferentes para a mesma padrão quando o app não está em inglês.

## SummaryRepository

`SummaryRepository.fetch(Month)` is one `GET /expenses/summary?month=YYYY-MM` (`Month.toQuery()`). A `2xx` body that
breaks the contract becomes a `ProblemFailure`, so callers handle one failure type. It is a separate interface from
`ExpenseRepository` on purpose: the summary is a read of a different resource (server-side totals), and the
ViewModel can be tested with a fake that returns any summary without building expenses.

**PT:** O `SummaryRepository.fetch(Month)` é um `GET /expenses/summary?month=YYYY-MM` (`Month.toQuery()`). Um corpo
`2xx` que quebra o contrato vira `ProblemFailure`, então quem chama trata um só tipo de falha. É uma interface
separada do `ExpenseRepository` de propósito: o resumo é a leitura de outro recurso (totais do servidor), e o
ViewModel pode ser testado com um fake que devolve qualquer resumo sem montar gastos.

## MonthComparison

This month against the previous one, all in `Decimal`. `difference` is `total - previous`, kept **positive**
(`abs`), and `direction` (`up`, `down`, `same`) says which way: the View writes "more than" or "less than" and never
sees a sign. `percent` is `difference / previous * 100`, also positive, and it is **null when the previous month is
0**: dividing by zero has no meaning, and "up infinity percent" is not information. In that case the pill says only
"Up" and the line below gives the amount. The division yields a `Rational`; it is converted with
`toDecimal(scaleOnInfinitePrecision: 4)` (truncated at 4 places, exact otherwise) and the View shows it with 1 place
(`formatPercent`). No `double` is involved, so `0.1 + 0.2` style sums stay exact.

**PT:** Este mês contra o anterior, tudo em `Decimal`. A `difference` é `total - previous`, mantida **positiva**
(`abs`), e a `direction` (`up`, `down`, `same`) diz o sentido: a View escreve "a mais" ou "a menos" e nunca vê um
sinal. O `percent` é `difference / previous * 100`, também positivo, e é **nulo quando o mês anterior é 0**: dividir
por zero não faz sentido, e "subiu infinito por cento" não é informação. Nesse caso a pílula diz só "Up" e a linha
abaixo dá o valor. A divisão produz um `Rational`; ele vira `Decimal` com `toDecimal(scaleOnInfinitePrecision: 4)`
(truncado em 4 casas, exato nos outros casos) e a View o mostra com 1 casa (`formatPercent`). Nenhum `double` entra,
então somas do tipo `0.1 + 0.2` continuam exatas.

## percent text

`formatPercent(Decimal, locale:, fractionDigits:)` (`core/l10n/percent_format.dart`) writes a percent with
`Decimal.toStringAsFixed` and swaps the `.` for the locale's decimal mark (`49,6` in `pt_BR`). The bar rows show the
API's `percentage` (`49.60` shown as `49.6`); nothing recomputes a share from the totals, because the API rounds
HALF_UP and the rounded shares may not add up to 100, which is expected ([contract](../api-contract.md)).

Known limits, all display only. **(1)** The category share is the API's 2-decimal HALF_UP string shown with 1
decimal, so it is rounded twice (`0.0449` becomes `0.04`, then `0.0`; at most 0.05 percentage points of drift).
**(2)** The comparison percent is truncated at 4 places and then rounded HALF_UP at 1, which is equivalent to one
exact HALF_UP rounding. **(3)** A tiny difference would read "Up 0.0%": `percentText` writes the sign through l10n
(`summaryPercent` = `{value}%`, so a language can place it) and returns `<0.1%` (`summaryPercentTiny`) for a value
above zero that would show as `0.0`. The "same" pill still needs a difference of exactly zero. The sign is part of
the l10n message on purpose: `Up {percent}` and `{count} expenses · {percent}` receive text that already has it.

**PT:** Limites conhecidos, todos só de exibição. **(1)** A fatia da categoria é a string da API com 2 casas HALF_UP
mostrada com 1 casa, então é arredondada duas vezes (`0.0449` vira `0.04`, depois `0.0`; no máximo 0,05 ponto
percentual de desvio). **(2)** O percentual da comparação é truncado em 4 casas e depois arredondado HALF_UP em 1, o
que equivale a um único arredondamento HALF_UP exato. **(3)** Uma diferença minúscula leria "Up 0.0%": o
`percentText` escreve o sinal pelo l10n (`summaryPercent` = `{value}%`, para um idioma poder posicioná-lo) e devolve
`<0.1%` (`summaryPercentTiny`) para um valor maior que zero que apareceria como `0.0`. A pílula "same" continua
exigindo diferença exatamente zero. O sinal faz parte da mensagem do l10n de propósito: `Up {percent}` e
`{count} expenses · {percent}` recebem um texto que já o tem.

**PT:** O `formatPercent(Decimal, locale:, fractionDigits:)` (`core/l10n/percent_format.dart`) escreve um percentual
com `Decimal.toStringAsFixed` e troca o `.` pelo separador decimal do locale (`49,6` em `pt_BR`). As linhas de barra
mostram o `percentage` da API (`49.60` aparece como `49.6`); nada recalcula uma fatia a partir dos totais, porque a
API arredonda HALF_UP e as fatias arredondadas podem não somar 100, o que é esperado ([contrato](../api-contract.md)).

## SummaryViewModel

State: `Loading(month)`, `Loaded(month, summary, comparison, failure?)` and `Failed(month, failure)`; the month is in
every state so the selector never loses it. It follows the expense list ViewModel on purpose:

- **One month at a time**, starting at the month of the injected `now` (the page takes `now`, tests pass a fixed
  one; a shared clock provider was not introduced: two features pass the same `DateTime.now` tear-off, which is
  small and explicit). `canGoNext` is false on the current month: nothing can be dated that far ahead.
- **A ticket** (`_ticket`) makes the newest request own the screen: a slow answer for a month the user already left
  never overwrites the newer one, and a retry or a reload after a write cancels the older request's result.
- **Reload on `ExpenseRepository.changes`.** The ViewModel listens and calls `refresh()`; it removes the listener in
  `dispose()` and never notifies after it. `refresh()` keeps the summary on screen: a failed reload becomes
  `failure` next to the old summary (a banner) instead of replacing it with an error page. Before anything loaded
  `refresh()` is a normal `load()`. The Summary tab and the Expenses tab live at the same time in the bottom bar,
  so both listen; saving an expense updates both.
- `isEmpty` is true when the month has no expense: the page offers "Add expense" instead of an empty chart.

**PT:** Estado: `Loading(month)`, `Loaded(month, summary, comparison, failure?)` e `Failed(month, failure)`; o mês
está em todo estado, então o seletor nunca o perde. Segue o ViewModel da lista de gastos de propósito:

- **Um mês por vez**, começando no mês do `now` injetado (a página recebe `now`, os testes passam um fixo; não se
  criou um provider de relógio compartilhado: duas features passam o mesmo tear-off `DateTime.now`, o que é pequeno
  e explícito). O `canGoNext` é falso no mês atual: nada pode ter data tão à frente.
- **Um ticket** (`_ticket`) faz a requisição mais nova ser dona da tela: uma resposta lenta de um mês que o usuário
  já deixou nunca sobrescreve a mais nova, e um retry ou um recarregar após uma escrita cancela o resultado da
  requisição mais velha.
- **Recarregar no `ExpenseRepository.changes`.** O ViewModel escuta e chama `refresh()`; remove o listener no
  `dispose()` e nunca notifica depois. O `refresh()` mantém o resumo na tela: um recarregar que falhou vira
  `failure` junto do resumo antigo (um banner) em vez de trocá-lo por uma página de erro. Antes de algo carregar o
  `refresh()` é um `load()` normal. A aba Resumo e a aba Despesas vivem ao mesmo tempo na barra inferior, então as
  duas escutam; salvar um gasto atualiza as duas.
- `isEmpty` é verdadeiro quando o mês não tem gasto: a página oferece "Add expense" em vez de um gráfico vazio.

## SummaryController

Only intents: start, retry, previous and next month, pull to refresh (returns the ViewModel's future so the spinner
ends with the answer) and "Add expense" from the empty state, which asks `AppNavigator.push(AppRoute.expenseNew)`.
Nothing waits for the form: the summary reloads itself through `changes` when the form saves.

**PT:** Só intenções: iniciar, tentar de novo, mês anterior e seguinte, puxar para atualizar (devolve o future do
ViewModel para o spinner terminar com a resposta) e "Add expense" a partir do estado vazio, que pede
`AppNavigator.push(AppRoute.expenseNew)`. Nada espera o formulário: o resumo recarrega sozinho pelo `changes`
quando o formulário salva.

## SummaryPage

A `MonthSelector` above a body that switches on the state: a spinner, `LoadError` ([`app-core.md`](app-core.md#loaderror); the message and a retry),
or `SummaryContent` (pull to refresh over a scroll view that is scrollable even when short, so an empty month can be
refreshed too). The loaded content is the failure banner (if a refresh failed), `SummaryTotalCard` and
`CategoryBreakdownChart`, or `SummaryEmptyState`. `SummaryTotalCard` is a `GradientCard` ([`app-core.md`](app-core.md#brandgradients))
with only white text: the total (`formatMoney`), the expense count, and a `PillChip` plus a line for the comparison
(`Up 25.0%` / "R$ 200.00 more than last month"; no percent when the previous month was 0). The pill and the line are
one `Semantics` sentence. All money goes through `formatMoney`; nothing here formats a number by hand.

**PT:** Um `MonthSelector` acima de um corpo que troca conforme o estado: um spinner, o `LoadError` ([`app-core.md`](app-core.md#loaderror); a
mensagem e um tentar de novo) ou o `SummaryContent` (puxar para atualizar sobre uma rolagem que rola mesmo curta,
então um mês vazio também pode ser atualizado). O conteúdo carregado é o banner de falha (se uma atualização
falhou), o `SummaryTotalCard` e o `CategoryBreakdownChart`, ou o `SummaryEmptyState`. O `SummaryTotalCard` é um
`GradientCard` ([`app-core.md`](app-core.md#brandgradients)) só com texto branco: o total (`formatMoney`), a
quantidade de gastos, e uma `PillChip` mais uma linha para a comparação (`Up 25.0%` / "R$ 200.00 more than last
month"; sem percentual quando o mês anterior foi 0). A pílula e a linha são uma só frase de `Semantics`. Todo
dinheiro passa pelo `formatMoney`; nada aqui formata número à mão.

## CategoryBreakdownChart

Decision (plan question Q1): **our own chart, no chart package.** The data is a short ranked list; horizontal bars
made of plain widgets (a track, a `FractionallySizedBox` fill) are enough, add no dependency, and are fully
accessible. A donut was left out (optional in the plan, not trivial to make readable).

- **Order** is the server's (biggest total first, ties by name); the widget never sorts.
- **Width** is the API's `percentage` as a `Decimal` divided by 100, then one `toDouble()` for layout only: the
  fraction is never shown or used for money. A real share never draws thinner than 2% of the track, so a 0.4%
  category is still visible; the number next to the bar is the real one.
- **One `Semantics` label per row** (`"Groceries, R$ 612.30, 49.6 percent of the total"`) with the visual pieces
  inside excluded, so a screen reader says each row once, not name, amount and percent as three stops.
- **Reduce motion.** The bars grow in 450 ms (`TweenAnimationBuilder`); when `MediaQuery.disableAnimationsOf` is
  true the duration is zero and they are drawn at their final width at once.
- The bars use the theme's `primary` on `surfaceContainerHighest` (not the gradient): they sit on the page
  background, where the brand blue has enough contrast; the white-on-gradient rule applies only to the card.

**PT:** Decisão (pergunta Q1 do plano): **gráfico próprio, sem pacote de gráfico.** Os dados são uma lista curta
ranqueada; barras horizontais de widgets simples (uma trilha, um preenchimento com `FractionallySizedBox`) bastam,
não adicionam dependência e são totalmente acessíveis. O donut ficou de fora (opcional no plano, não trivial de
deixar legível).

- A **ordem** é a do servidor (maior total primeiro, empates por nome); o widget nunca ordena.
- A **largura** é o `percentage` da API como `Decimal` dividido por 100, e um único `toDouble()` só para o layout:
  a fração nunca é mostrada nem usada para dinheiro. Uma fatia real nunca é desenhada com menos de 2% da trilha,
  então uma categoria de 0,4% ainda aparece; o número ao lado da barra é o real.
- **Um rótulo `Semantics` por linha** (`"Groceries, R$ 612.30, 49.6 percent of the total"`) com as peças visuais
  dentro excluídas, então o leitor de tela diz cada linha uma vez, não nome, valor e percentual como três paradas.
- **Reduzir movimento.** As barras crescem em 450 ms (`TweenAnimationBuilder`); quando
  `MediaQuery.disableAnimationsOf` é verdadeiro a duração é zero e elas são desenhadas já na largura final.
- As barras usam o `primary` do tema sobre `surfaceContainerHighest` (não o gradiente): ficam sobre o fundo da
  página, onde o azul da marca tem contraste suficiente; a regra branco-sobre-gradiente vale só para o card.
