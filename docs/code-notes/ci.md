# CI (GitHub Actions)

Notes for `.github/workflows/api.yml`, `.github/workflows/app.yml` and `.github/dependabot.yml`.
Why the pipelines are shaped this way; the monorepo decision is in
[ADR 0001](../decisions/0001-monorepo.md).

**PT:** Notas dos workflows do GitHub Actions e do Dependabot. Explicam por que os pipelines têm
esta forma; a decisão do monorepo está no [ADR 0001](../decisions/0001-monorepo.md).

## paths-filters

There are two workflows, one per part of the monorepo. Each one runs only when its own folder, the
API contract or the workflow file itself changes (`api/**` or `app/**`, `docs/api-contract.md`,
`.github/workflows/<name>.yml`; the app one also watches `scripts/ci/**`, where its coverage script
lives). A change that only touches the app does not start a Maven build
with Testcontainers, and the other way around. The contract is in both lists because both sides
depend on it. A third-party path-filter action was rejected: the built-in `paths:` is enough and
adds no dependency.

Trade-off: if a workflow becomes a *required* status check in branch protection, a PR that skips it
because of `paths:` stays "pending" forever. Add a required check only after deciding how to handle
that (for example an always-running aggregate job).

**PT:** Dois workflows, um por parte do monorepo. Cada um roda só quando a própria pasta, o
contrato da API ou o próprio arquivo do workflow mudam. Assim uma mudança só no app não dispara o
build Maven com Testcontainers, e vice-versa. O contrato está nas duas listas porque os dois lados
dependem dele. Trade-off: se um workflow virar check obrigatório na proteção de branch, um PR que
o pula por causa do `paths:` fica "pendente" para sempre; decida isso antes de exigir o check.

## Permissions and secrets

Every workflow declares `permissions: contents: read` at the top, so the `GITHUB_TOKEN` can only
read the repository. A compromised dependency or action then cannot push commits or change
releases. `actions/checkout` uses `persist-credentials: false`: no step pushes, so the token is not
written to `.git/config`.

No repository secrets are used. The API tests generate their own keys and Testcontainers starts a
throwaway PostgreSQL on the runner's Docker. The workflows never use `pull_request_target`, which
runs with a write token and secrets on code from a fork. A workflow without secrets cannot leak
them, even on a pull request from a fork. Pull requests opened by Dependabot also get a read-only
token and only Dependabot secrets, and there are none.

**PT:** `permissions: contents: read` no topo deixa o token só com leitura, então uma action ou
dependência comprometida não consegue dar push nem mexer em releases. O `persist-credentials: false`
evita deixar o token no `.git/config`. Não há secrets no repositório: os testes geram as próprias
chaves e o PostgreSQL é descartável. Nunca se usa `pull_request_target` (ele roda com token de
escrita e secrets sobre código de fork).

## SHA pinning

Every action, first-party included, is pinned by the full 40-character commit SHA, with the version in a comment
(`uses: owner/repo@<sha> # v1.2.3`). A tag such as `v4` can be moved to different code by whoever
controls the action's repository; a commit SHA cannot. Dependabot (`github-actions` ecosystem)
opens weekly PRs that update both the SHA and the comment, so pinning does not freeze the versions.

To add an action: resolve the SHA of the release tag (for example
`git ls-remote https://github.com/OWNER/REPO 'refs/tags/vX.Y.Z*'`; if an annotated tag shows a
`^{}` line, use that one, it is the commit) and write the tag in the comment.

**PT:** Todas as actions (inclusive as oficiais) ficam fixadas pelo SHA completo do commit, com a versão em comentário.
Uma tag (`v4`) pode ser movida pelo dono da action; um SHA não. O Dependabot abre PRs semanais que
atualizam SHA e comentário, então fixar não congela as versões.

## Concurrency and timeouts

`concurrency` groups runs by workflow and ref with `cancel-in-progress: true`: a new push to the
same branch cancels the obsolete run and saves runner minutes. Each job has `timeout-minutes` so a
hung Testcontainers or Flutter step cannot burn the default six hours.

**PT:** O `concurrency` cancela a execução antiga quando chega um push novo na mesma branch, e o
`timeout-minutes` impede que um job travado consuma o limite padrão de seis horas.

## Versions

The app workflow pins Flutter `3.47.0` (stable), the same version as `app/CLAUDE.md`; when the
SDK is bumped, change both. The API workflow uses Temurin 21 and the Maven wrapper, with the Maven
cache from `actions/setup-java`.

`flutter analyze --fatal-infos` makes info-level lints fail the build. There is no
`dart format --set-exit-if-changed` yet: it needs a repository-wide format commit first.

**PT:** O workflow do app fixa Flutter `3.47.0`, igual ao `app/CLAUDE.md`; ao subir o SDK, mude
os dois. `--fatal-infos` faz lints de nível info quebrarem o build. O `dart format` como gate ainda
não existe: antes é preciso um commit de formatação do repositório inteiro.

## Coverage

What is gated: the API **service packages** (`**/service/*` classes), lines and branches, with
JaCoCo; and the app **ViewModels** (`*_view_model.dart`), lines, with
`scripts/ci/check_app_coverage.sh`. Nothing else is gated. Services and ViewModels hold the business
rules and the UI state rules, and they are tested in isolation (Mockito / fakes), so their number
means something. A global percentage would be pushed up by DTOs, entities, mappers and generated
code, or pushed down by widgets and configuration that are better proven by integration and page
tests; a gate on it would reward writing trivial tests. Controllers, repositories and views are
covered by tests that prove contract and behavior, not by a percentage.

How the threshold was chosen: measure the baseline, gate at `floor(baseline) - 2` points, with a
minimum of 80% lines. The 2 points leave room for a small refactor without a red build, but a
removed test file for a large service or ViewModel still fails (about 13 service lines and 12
ViewModel lines may stay uncovered, so the test of a small class can disappear unnoticed).

| Scope | Counter | Baseline (2026-11-23) | Gate |
|---|---|---|---|
| API services (13 classes) | lines | 98.79% (327/331) | 96% (`jacoco.service.line.minimum=0.96`) |
| API services | branches | 100% (78/78) | 98% (`jacoco.service.branch.minimum=0.98`) |
| App ViewModels (11 files) | lines | 100% (610/610) | 98% (argument of the script in `app.yml`) |

Where the numbers live: the API gate is in `api/pom.xml` (properties, so a command line can
override them: `./mvnw verify -Djacoco.service.line.minimum=0.995` must fail while the baseline is
below it). The app gate is the second argument of `check_app_coverage.sh` in
`.github/workflows/app.yml`. When a baseline moves up for good, raise the gate in the same change.

How it works:

- JaCoCo `prepare-agent` puts its agent in the `argLine` property; Surefire's
  `@{argLine} -javaagent:<mockito>` runs both agents (`@{...}` is read late, after `prepare-agent`
  ran; `${...}` would be read too early and lose the JaCoCo agent). The `pom.xml` also defines an
  empty `argLine` so tests still run with `-Djacoco.skip=true`.
- The `check` goal limits the classes with its own `<includes>` (class-file patterns). A rule-level
  `<include>` matches the *element name* (the bundle name for `BUNDLE`), so it would silently select
  nothing and the gate would always pass; this was seen while building it.
- The app script reads the `lcov.info` records (`SF:` file, `LF:` lines found, `LH:` lines hit),
  keeps only the paths ending in `_view_model.dart`, adds `LH` and `LF` and compares the percentage.
  It fails (exit 1) under the minimum and also when it finds no ViewModel at all, so a renamed
  folder cannot make the gate pass by measuring nothing.
- No external service (no Codecov): each run writes the percentages to the job summary
  (`$GITHUB_STEP_SUMMARY`) and uploads the JaCoCo HTML report (`api-jacoco-report`) and
  `lcov.info` (`app-lcov`) as artifacts kept for 14 days. A badge service can be added later.
- `actions/upload-artifact` is pinned by SHA like every action (v7.0.2). The summary step uses
  plain `awk`, no third-party action.

See it locally:

```bash
cd api && ./mvnw verify && open target/site/jacoco/index.html   # macOS; HTML report
cd app && flutter test --coverage                              # writes coverage/lcov.info
../scripts/ci/check_app_coverage.sh coverage/lcov.info 98      # per-file and total percentage
```

`api/target/` and `app/coverage/` are git-ignored.

**PT:** O que tem gate: só as classes de `service` da API (linhas e branches, JaCoCo) e os
ViewModels do app (linhas, script awk). Serviços e ViewModels concentram as regras e são testados
isolados, então o percentual deles significa algo; um percentual global seria inflado por DTOs e
código gerado. Limite = `floor(baseline) - 2`, mínimo 80% de linhas. Baselines: services 98,79%
linhas e 100% branches (gate 96% e 98%); ViewModels 100% (gate 98%). O `@{argLine}` do Surefire é
lido tarde e junta o agente do JaCoCo com o do Mockito. Sem serviço externo: percentuais no resumo
do job e relatórios como artifacts por 14 dias. Ver local: `open api/target/site/jacoco/index.html`
e `flutter test --coverage`.

Vocabulary / Vocabulário: *gate* = barreira que quebra o build; *baseline* = medida inicial;
*threshold* = limite mínimo; *artifact* = arquivo guardado pela execução do CI.

## Dependabot

`dependabot.yml` checks `maven` (`/api`), `pub` (`/app`) and `github-actions` (`/`) weekly, one
grouped PR per ecosystem to keep the noise low. The `docker` ecosystem is added when the
Dockerfiles exist.

**PT:** O Dependabot verifica maven, pub e github-actions toda semana, com um PR agrupado por
ecossistema. O ecossistema `docker` entra quando os Dockerfiles existirem.
