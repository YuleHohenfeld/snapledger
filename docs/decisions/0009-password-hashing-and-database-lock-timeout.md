# 0009. Password hashing cost, hashing outside the transaction, and a database lock timeout

- Status: Accepted
- Date: 2026-11-13

## Context

Register and login (Increment 2 Step 3) are the first endpoints that do expensive work per request
and hold database resources while they do it. Three related questions came up:

1. **Which password encoder and which cost.** Spring offers a plain `BCryptPasswordEncoder` and a
   `DelegatingPasswordEncoder` (`{bcrypt}$2a$...`, lets several algorithms coexist). The bcrypt cost
   decides how slow offline cracking is, but also how much CPU every login and register burns on
   the server. `/auth/*` has no rate limit until Phase 4.
2. **Where bcrypt runs relative to the transaction.** Register must be atomic (contract: the account
   and its session are created together or not at all). With `@Transactional` on `register`, the
   transaction (and a pool connection) is taken before the method body runs, so the connection is
   held, idle, for the whole bcrypt (tens of milliseconds). A burst of registrations could exhaust
   the pool (10 connections by default) with connections that are only waiting for CPU work.
3. **How long a statement may wait for a row lock.** PostgreSQL's default `lock_timeout` is 0:
   wait forever. A refresh rotation blocked on its family row (ADR 0008) or a register blocked on an
   uncommitted insert of the same email would hold a pool connection until the other transaction
   ends.

## Decision

**1. Plain `BCryptPasswordEncoder`, cost pinned to 10** (`SecurityConfig.BCRYPT_COST`).

- 10 is the minimum the OWASP Password Storage Cheat Sheet accepts for bcrypt and Spring's
  default; it is written down so a library upgrade cannot change it silently.
- Not higher for now: every login and register pays the cost on the server CPU, and without a
  rate limit (Phase 4) a higher cost makes the API cheaper to overload (a CPU DoS trade-off).
- Not `DelegatingPasswordEncoder`: the schema already limits the column to bcrypt
  (`varchar(72)`, `ck_users_password_hash_bcrypt`), so a new algorithm needs a migration and an
  ADR anyway. The CHECK also accepts the `{bcrypt}` prefix, so switching later needs no data change.
  Until then that tolerance is a gap (a prefixed hash would never match the plain encoder); the
  roadmap item closes it, and whichever comes first wins: tightening the CHECK to plain bcrypt in
  the next `users` migration, or switching to `DelegatingPasswordEncoder`.
- A future cost change applies to new hashes only (the cost is stored in each hash). Upgrading
  existing users needs `upgradeEncoding` checked on a successful login, with a re-hash and an
  update. During the transition, users with old and new costs take different times to log in, and
  the dummy hash (unknown email) has the new cost: a small timing signal that tells "old account"
  apart from "unknown email" until every active account is upgraded. Accepted for that window;
  tracked in the roadmap.

**2. Hash first, then open the transaction.** `AuthService.register` is not annotated
`@Transactional`. It calls `passwordEncoder.encode` with no transaction and no connection, then
runs `UserService.create`, `RefreshTokenService.startFamily` and the access token inside **one**
`TransactionTemplate.execute`, so atomicity is unchanged (`create` and `startFamily` join it). The
template is built in the constructor from the injected `PlatformTransactionManager`, Spring's
documented pattern, so its settings belong to `AuthService` and nobody can change them through the
shared, mutable `TransactionTemplate` bean. Login already had no outer transaction (bcrypt runs
between the read-only lookup and `startFamily`). Rule in `api/CLAUDE.md`: `@Transactional` stays
the default; a `TransactionTemplate` is used only when slow non-database work must run before the
transaction opens.

**3. `lock_timeout = 3s` on every pool connection**, as a pgjdbc startup option
(`spring.datasource.hikari.data-source-properties.options=-c lock_timeout=3s`).

- A startup option becomes the session default, so `RESET ALL` / `DISCARD ALL` return to 3 s
  instead of to 0. `SET` through Hikari's `connection-init-sql` would be undone by them.
  `DatabaseConnectionSettingsTest` proves both the value and the `RESET ALL` behavior.
- A wait past it fails with `55P03`, translated to `CannotAcquireLockException`. It is not an
  `ApiException`, so it ends as a masked `500 internal-error`. It must **never** be translated into
  a `401` (`invalid-refresh-token` would make the app wipe a healthy session) or a `409`.
- It also applies to Flyway, which uses the same data source. That is fine and wanted: Flyway's
  own PostgreSQL migration lock uses `pg_try_advisory_lock` in a retry loop (checked in
  `flyway-database-postgresql` 12.4.0), which never waits on a lock, so `lock_timeout` does not
  affect it. A migration whose DDL waits more than 3 s for a table lock fails and rolls back (each
  migration is a transaction on PostgreSQL), and the application does not start; it does not sit
  in the lock queue blocking live traffic behind it. The fix is to retry the deploy when the table
  is quiet.

## Consequences

- No pool connection is held during bcrypt on register or login.
- `AuthService` is the one service that uses `TransactionTemplate`; its test checks the order
  (hash, then begin, create, session, commit), and `AuthIntegrationTest` checks that no transaction
  is active while the password is hashed.
- Login and register stay CPU-bound at about one bcrypt each, which a rate limit (Phase 4) must
  bound. Raising the cost later needs `upgradeEncoding` on login and accepts the timing gap above.
- Any lock wait over 3 s is a `500`, never a domain error. Increment 3 (`rotate`) must not catch it.
- A long migration that needs a lock on a busy table must be deployed when it can get it in 3 s,
  or set its own `SET LOCAL lock_timeout` inside the migration.

## Alternatives considered

- **`@Transactional` on register, hash inside** (the first version): simplest, but holds a
  connection during bcrypt. Rejected.
- **Hash in the controller or in a separate bean method** so that `@Transactional` stays on the
  service: moves a security rule out of the service, or adds a public method whose only reason is
  proxy mechanics. Rejected.
- **Inject the auto-configured `TransactionTemplate` bean**: works, but it is a shared mutable
  object, and the service would depend on Boot's auto-configuration instead of the transaction
  manager. Rejected.
- **`DelegatingPasswordEncoder`**: see point 1. Can be adopted later without data changes.
- **Cost 12 or more**: stronger offline, but too expensive per request without a rate limit.
  Revisit with Phase 4.
- **`statement_timeout` instead of `lock_timeout`**: would also cut legitimately slow queries.
  Rejected; the problem is waiting for locks.
- **`SET lock_timeout` in `connection-init-sql`**: lost on `RESET ALL`. Rejected.

## References

- [OWASP Password Storage Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Password_Storage_Cheat_Sheet.html)
- [Spring Framework: programmatic transaction management (`TransactionTemplate`)](https://docs.spring.io/spring-framework/reference/data-access/transaction/programmatic.html)
- [PostgreSQL: `lock_timeout`](https://www.postgresql.org/docs/17/runtime-config-client.html#GUC-LOCK-TIMEOUT)
- [PostgreSQL: `RESET`](https://www.postgresql.org/docs/17/sql-reset.html)
