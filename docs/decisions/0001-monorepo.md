# 0001. Monorepo for app and API

- Status: Accepted
- Date: 2026-11-10

## Context

SnapLedger has two deployable parts: a Flutter app (iOS, Android, Web) and a Spring Boot API.
They are developed by one person, change together often (a new endpoint usually means a new
screen), and share one contract (`docs/api-contract.md`).

The project is also a public portfolio: a reviewer should be able to clone it once, read
how the parts fit together and run everything locally.

## Decision

Keep both parts in **one Git repository**:

```
snapledger/
├── app/        Flutter app (own pubspec, own tooling)
├── api/        Spring Boot API (own pom.xml and Maven wrapper)
├── docs/       contract, ADRs, architecture, roadmap (shared)
├── scripts/    automation shared by both
└── docker-compose.yml, .env.example
```

Rules that keep the monorepo healthy:

- `app/` and `api/` do not import each other's code. The **only** link between them is the
  HTTP contract in `docs/api-contract.md`.
- Each part keeps its own build tool, dependencies and `CLAUDE.md`. Nothing at the root
  needs both toolchains.
- A change that touches the contract updates the contract, the API and the app in the same
  pull request, so they are never out of sync on `develop`.
- Commit scopes say which part changed: `feat(api)`, `feat(app)`, `docs`, `chore`.
- CI (Phase 4) runs each part's pipeline only when its folder (or `docs/api-contract.md`) changed.

## Consequences

- One clone, one README, one place for issues and history. Easier to review and to demo.
- Contract changes are atomic: the API and the app that depend on them are reviewed together.
- Shared docs, ADRs, hooks and agents live in one place instead of being duplicated.
- The repository mixes two ecosystems (Dart and Java). Tools and IDE settings must be scoped
  to their folder.
- CI needs path filters to avoid building the app when only the API changed (and vice versa).
- Both parts share one version history. Independent release versions, if ever needed, must
  use prefixed tags (`api-v1.2.0`, `app-v1.3.0`).

## Alternatives considered

- **Two repositories (polyrepo)**: clear ownership and independent CI, but every contract
  change becomes two coordinated pull requests and the portfolio is split in two places.
  Worth it with separate teams or release cycles, which this project does not have. Rejected.
- **Monorepo tooling (Nx, Bazel, Melos + Maven multi-module)**: useful with many packages
  and shared libraries. Here there are two independent parts and no shared code, so the
  extra tooling would add complexity without benefit. Rejected for now; revisit if shared
  packages appear.

## When to revisit

If the app and the API get separate maintainers, separate release cadences, or the repository
becomes slow to work with, write a new ADR to split them.
