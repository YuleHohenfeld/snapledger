# SnapLedger — project rules

SnapLedger is a personal expense tracker and a **public portfolio project**: users sign up,
log in, record expenses by category and see a monthly summary with a chart. In a later
phase, AI reads a photo of a receipt and pre-fills the expense.

These rules apply to the whole repository. Folder-specific rules live next to the code:
[`api/CLAUDE.md`](api/CLAUDE.md) (Spring Boot) and [`app/CLAUDE.md`](app/CLAUDE.md) (Flutter).
When two rules conflict, the more specific file wins; if that still seems wrong, ask.

## Communication

- Talk to the owner in **Portuguese**. Code, docs, the API contract, commit messages and
  every file in this repo are in **English**.
- **Code comments are short and bilingual** (the owner is learning English): at most one
  English sentence saying what the element guarantees, or a warning the caller must see, then
  its Portuguese translation prefixed with `PT:`. The long **why** lives in
  `docs/code-notes/<area>.md` (bilingual, see [`docs/code-notes/README.md`](docs/code-notes/README.md)),
  linked from the code with `Notes: docs/code-notes/<area>.md#<anchor>` (SQL:
  `-- Notes / Notas: ...`). When the code changes, update its comment, its `PT:` translation and
  its note in the same change. Comments never narrate the code.
- Explain the **why** before creating a file, and say where the pattern is used in the industry.
- If scope, layer or ownership of a piece of logic is unclear, **stop and ask**. Asking is a
  success; confident code built on a wrong assumption is the worst outcome.
- Never copy code, names, texts or business rules from other codebases. This repo is
  public and everything in it must be original.

## Repository map

| Path | What lives there |
|---|---|
| `app/` | Flutter app (iOS, Android, Web), MVVMC with Provider ([ADR 0010](docs/decisions/0010-app-architecture-mvvmc-provider.md)) |
| `api/` | Spring Boot 4 + Java 21 REST API |
| `docs/api-contract.md` | **Source of truth** between app and API |
| `docs/decisions/` | ADRs: why important decisions were made |
| `docs/code-notes/` | The long why behind code comments, one file per area (bilingual), linked from the code |
| `docs/architecture.md`, `docs/roadmap.md` | Big picture and phases |
| `.claude/agents/`, `.claude/skills/` | Agents and pattern skills used to build this project |
| `scripts/claude/` | Hook scripts that check project rules automatically |
| `docker-compose.yml`, `.env.example` | Local infrastructure and environment template |

## Golden rules

1. **Contract first.** No endpoint, field or error exists unless it is in
   `docs/api-contract.md`. Change the contract and the code in the same change.
2. **Secrets only in environment variables.** Never in code, config files, tests, docs or logs.
   `.env` is git-ignored and must never be read or printed.
3. **The user comes from the token.** Never from a request field. Another user's data → `404`.
4. **Expensive or security-related decisions get an ADR** in `docs/decisions/`.
5. **Follow the sibling.** New code follows the closest existing feature; consistency beats
   local cleverness.
6. **Tests are part of the change**, not a follow-up.

## Task triage: which agent for which situation

At the start of any coding request, say which row applies and which agent you will use.
If the request fits more than one row (for example "take a look at this"), ask first.

| Situation | Step 1 | Step 2 |
|---|---|---|
| New feature or endpoint | `planner` → **owner approves the plan** | `implementer`, then the reviewers below |
| Bug, cause known | `implementer` | reviewers for the touched area |
| Bug, cause unknown | Investigate in the main session (read, reproduce, find the cause) | `implementer` with the confirmed cause |
| Check API architecture | `api-reviewer` (pass the changed files) | — |
| Check app architecture | `mvvmc-reviewer` (pass the changed files) | — |
| Touched auth, tokens, security config, CORS, properties, secrets; in the app: `core/{api,session,storage,config}`, `features/auth`, `pubspec.yaml`, platform config | `security-reviewer` (required; the Stop hook enforces it) | — |
| Find bugs in a diff | `/code-review` | — |
| Question about existing code | Answer directly in the conversation | — |

### New feature flow

1. `planner` returns a file-by-file plan (no code). Its open questions go to the owner.
2. **Mandatory stop: the owner approves the plan.**
3. `implementer` writes the code and tests, then runs compile/analyze and the related tests.
4. Reviewers run on the list of new/changed files: `api-reviewer` and/or `mvvmc-reviewer`,
   plus `security-reviewer` when required.
5. Findings are fixed in **one** round; then stop and let the owner decide.
6. Report: files created/changed, how it was verified, what is left, suggested commit messages.

Every agent starts without this conversation: pass it the original request, the approved
plan and, for reviewers, the list of changed files.

## Git

- Work on `develop`. `main` receives only reviewed, working states.
- [Conventional Commits](https://www.conventionalcommits.org/) with scope:
  `feat(api)`, `feat(app)`, `fix(...)`, `test(...)`, `refactor(...)`, `docs`, `chore`.
  One subject per commit; the subject is imperative and lowercase (`add`, not `Added`).
- Commit only when the owner asks. **Never push**: the owner reviews and pushes
  (blocked in `.claude/settings.json`).

## Commands

```bash
# Infrastructure (repo root)
cp .env.example .env            # once; fill POSTGRES_PASSWORD and JWT_SECRET
docker compose up -d            # PostgreSQL 17
docker compose down             # stop (data kept)

# API (Java 21: run `java21` first; the machine default is Java 17)
cd api && ./mvnw -q compile
cd api && ./mvnw test
cd api && ./mvnw spring-boot:run

# App (if `flutter` is not on PATH: export PATH="$HOME/Documents/development/flutter/bin:$PATH")
cd app && flutter pub get
cd app && flutter analyze && flutter test
cd app && flutter run --dart-define=API_BASE_URL=http://localhost:8080
cd app && flutter run -d chrome --web-port 8081 --dart-define=API_BASE_URL=http://localhost:8080
```

## Automatic checks

`.claude/settings.json` registers hooks (`scripts/claude/`): after each edit the edited file
is checked against the project rules (`api_rules.sh`, `mvvmc_rules.sh`); before a response ends,
all changed files are checked, the API is compiled, the app is analyzed (`flutter analyze`) and
the security review is requested when needed. The rule tables live
in each folder's `CLAUDE.md`. If a hook blocks you, fix the cause. Never disable or bypass a hook.
