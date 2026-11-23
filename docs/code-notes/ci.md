# CI (GitHub Actions)

Notes for `.github/workflows/api.yml`, `.github/workflows/app.yml` and `.github/dependabot.yml`.
Why the pipelines are shaped this way; the monorepo decision is in
[ADR 0001](../decisions/0001-monorepo.md).

**PT:** Notas dos workflows do GitHub Actions e do Dependabot. Explicam por que os pipelines têm
esta forma; a decisão do monorepo está no [ADR 0001](../decisions/0001-monorepo.md).

## paths-filters

There are two workflows, one per part of the monorepo. Each one runs only when its own folder, the
API contract or the workflow file itself changes (`api/**` or `app/**`, `docs/api-contract.md`,
`.github/workflows/<name>.yml`). A change that only touches the app does not start a Maven build
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

## Dependabot

`dependabot.yml` checks `maven` (`/api`), `pub` (`/app`) and `github-actions` (`/`) weekly, one
grouped PR per ecosystem to keep the noise low. The `docker` ecosystem is added when the
Dockerfiles exist.

**PT:** O Dependabot verifica maven, pub e github-actions toda semana, com um PR agrupado por
ecossistema. O ecossistema `docker` entra quando os Dockerfiles existirem.
