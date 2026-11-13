# 0008. A family row serializes refresh token rotation and revocation

- Status: Accepted
- Date: 2026-11-13
- Refines: [ADR 0002](0002-refresh-token-rotation.md)

## Context

ADR 0002 rotates refresh tokens inside one family and revokes the whole family on logout or
reuse. The first schema kept the state on the token rows only: `refresh_tokens.revoked_at`,
and revocation was

```sql
update refresh_tokens set revoked_at = :now where family_id = :f and revoked_at is null
```

PostgreSQL runs at **READ COMMITTED**: each statement sees the rows committed before it
started. A rotation is a transaction that marks token `Tn` used and **inserts** `Tn+1`. If a
revocation runs while that rotation is still open:

1. the revocation's `UPDATE` waits for the lock on `Tn` (the rotation updated it), then
   revokes `Tn`;
2. `Tn+1` is not in the revocation's snapshot (uncommitted when the statement started), so it
   is **not revoked**;
3. the rotation commits and hands `Tn+1` and a fresh access token to the client.

After a logout, or after reuse detection that was meant to kill a stolen session, one token
of the family survives. Whoever holds it keeps the session for up to 30 days. This is the
classic "phantom insert" problem: a row-by-row revocation cannot see a row that does not
exist yet.

## Decision

Add a table `refresh_token_families` that owns the **session state**, and make its row the
serialization point between rotation and revocation.

| Column | Purpose |
|---|---|
| `id` UUID | Primary key, the `family_id` of ADR 0002 |
| `user_id` UUID | Owner (FK to `users`, `on delete cascade`, indexed) |
| `created_at` | Session start (login or register) |
| `revoked_at` | Set once on logout or reuse; `null` while the session is active |

`refresh_tokens.family_id` becomes a foreign key to it (indexed, `on delete cascade`).
`refresh_tokens.user_id` and `refresh_tokens.revoked_at` are removed: owner and revocation
have **one** source of truth, so they can never disagree.

The family row exists **before** any rotation starts, so both flows can meet on it:

| Flow | First statement | Then |
|---|---|---|
| Rotation | `select ... from refresh_token_families where id = :f and revoked_at is null for no key update` (`@Lock(PESSIMISTIC_WRITE)`, `lockActive`). Empty → `401` | check expiry (expired → `401`, **not** reuse); `markUsed(Tn)`; `0` → reuse: revoke the family, `401`; else insert `Tn+1` |
| Logout / reuse | `update refresh_token_families set revoked_at = :now where id = :f and revoked_at is null` (`revoke`) | nothing else: every token checks its family |

Consuming a token also checks the family and the expiry, as defense in depth:

```sql
update refresh_tokens set used_at = :now
where id = :id and used_at is null and expires_at > :now
  and exists (select 1 from refresh_token_families f where f.id = family_id and f.revoked_at is null)
```

What happens in each order:

- **Rotation first**: it holds the family row; the revocation's `UPDATE` waits. When the rotation
  commits, the revocation updates the family, and from that moment `Tn+1` (and any other token of
  the family) cannot be consumed. The rotation happened before the logout, which is a correct order.
- **Revocation first**: it holds the family row; the rotation's lock waits. When the revocation
  commits, PostgreSQL re-checks `revoked_at is null` on the new row version and returns nothing:
  the rotation answers `401` and issues no token.

Lock order is always **family, then tokens**, in both flows, so they cannot deadlock each other.
`FOR NO KEY UPDATE` (what Hibernate 7 renders for `PESSIMISTIC_WRITE` on PostgreSQL) conflicts
with the revocation's `UPDATE` and with another rotation, but not with the foreign-key check of
the token the rotation itself inserts.

Two concurrent rotations of the same token also meet on the family row: the second waits, then
`markUsed` returns `0`, which ADR 0002 already treats as reuse.

Tests with real concurrent transactions (`RefreshTokenFamilyRepositoryTest`) prove both orders.
They wait until PostgreSQL reports a transaction blocked on a lock (`pg_stat_activity`), so they
do not depend on sleeps, and they fail if `lockActive` loses its lock.

## Consequences

- Logout and reuse detection kill the whole session, including a token a concurrent rotation
  was issuing.
- Revocation is one row update instead of one update per token.
- Every rotation takes a row lock on its family for a few milliseconds. Only requests of the
  **same session** wait for each other, which the single-flight client (ADR 0002) already avoids.
- The rotation must call `lockActive` first. This is a rule for `RefreshTokenService`, written in
  the `auth-flow` skill and in the repository Javadoc; `markUsed`'s family check limits the damage
  if it is forgotten, but does not close the race on its own.
- An expired token makes `markUsed` return `0` too. The service checks expiry before `markUsed`,
  so an expired token is answered `401` without revoking the session.
- The token row no longer carries `user_id`: the user comes from the locked family.
- A family whose tokens all expired stays as a row. The Phase 4 cleanup job deletes old families
  (tokens go with them through `on delete cascade`).

## Alternatives considered

- **Keep per-row revocation** (`update refresh_tokens ... where family_id = :f`): cannot see a
  token inserted by an uncommitted rotation (the race above). Rejected.
- **`NOT EXISTS (revoked token in family)` in `markUsed`** or a family check only in `markUsed`:
  the subquery reads the snapshot taken when the statement starts, so a revocation that commits
  right after it still lets the rotation insert and return `Tn+1` with a fresh access token. It
  limits the damage (the next rotation fails) but the client still gets a valid access token after
  logout. Kept only as defense in depth.
- **`SERIALIZABLE` isolation for rotation and logout**: PostgreSQL would detect the conflict and
  abort one transaction with a serialization failure. Every caller would need a retry loop, the
  failure surfaces as an exception that must not become a `500`, and it is easy to forget on one
  path. A single row lock is simpler and explicit. Rejected.
- **Conditional `UPDATE` on the family as the rotation's lock** (for example
  `set last_rotated_at = :now where id = :f and revoked_at is null`, returning the count): also
  serializes, but needs a column that exists only to be written, and does not return the owner.
  `SELECT ... FOR NO KEY UPDATE` locks and returns the row (with `user_id`) in one statement.
  Rejected.
- **Advisory locks** (`pg_advisory_xact_lock(hash(family_id))`): work, but are invisible in the
  schema, need native SQL and a hash of the UUID. Rejected.

## References

- [PostgreSQL: Transaction Isolation, Read Committed](https://www.postgresql.org/docs/17/transaction-iso.html#XACT-READ-COMMITTED)
- [PostgreSQL: Explicit Locking, row-level locks](https://www.postgresql.org/docs/17/explicit-locking.html#LOCKING-ROWS)
- [OAuth 2.0 Security Best Current Practice (RFC 9700), §4.14 Refresh Token Protection](https://www.rfc-editor.org/rfc/rfc9700)
