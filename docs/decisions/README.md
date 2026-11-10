# Architecture Decision Records

Short documents that capture **why** an important technical decision was made: the
context, the decision, its consequences and the alternatives that were rejected.
Format based on [Michael Nygard's ADRs](https://cognitect.com/blog/2011/11/15/documenting-architecture-decisions).

| # | Title | Status |
|---|---|---|
| 0001 | Monorepo for app and API | Planned |
| [0002](0002-refresh-token-rotation.md) | Opaque refresh tokens with rotation and reuse detection | Accepted |
| [0003](0003-ai-key-backend-only.md) | AI provider key lives only in the backend | Accepted |
| [0004](0004-jwt-resource-server.md) | Validate JWTs with Spring's OAuth2 Resource Server | Accepted |

## Rules

- One decision per file: `NNNN-kebab-case-title.md`, numbered in order, never reused.
- An accepted ADR is not rewritten. To change a decision, write a new ADR that
  **supersedes** the old one and update the old one's status to `Superseded by NNNN`.
- Write an ADR when a decision is expensive to reverse, affects security, or would make a
  newcomer ask "why is it done like this?".

## Template

```markdown
# NNNN. Title

- Status: Proposed | Accepted | Superseded by NNNN
- Date: YYYY-MM-DD

## Context
What problem or force makes this decision necessary?

## Decision
What we will do, stated plainly.

## Consequences
What gets easier, what gets harder, what we must now take care of.

## Alternatives considered
Each option and why it was rejected.
```
