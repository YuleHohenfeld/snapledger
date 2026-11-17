# 0012. Account codes: format, hashing, limits and storage

- Status: Accepted
- Date: 2026-11-17

## Context

Phase 1.5 adds two flows that prove access to an email: verifying the account email and resetting a
forgotten password. Both send a short code by email. A code is a weak secret (a million values),
so what protects it is not its entropy but how it is stored, how long it lives and how often it can
be tried or requested. Questions to settle: the code format, how it is stored, how it is bound to
what it unlocks, the limits, and where the counters live.

## Decision

**1. Format.** Six digits from `SecureRandom`, zero-padded (`000042`). Easy to type on a phone and
to copy from an email; the limits below, not the length, make guessing impractical.

**2. Storage: HMAC-SHA256 keyed by `ACCOUNT_CODE_SECRET`, lowercase hex.**

| Option | Verdict |
|---|---|
| Plain SHA-256 (what refresh tokens use, ADR 0002) | Rejected: refresh tokens have 256 bits of entropy, so a fast hash is enough. A code has 20 bits: anyone who reads the table could brute-force every hash in a millisecond. |
| bcrypt | Rejected: it would protect against that, but the cost (tens of ms per check, ADR 0009) buys little when the limits already cap guesses at 5, and it needs hashing outside the transaction for no gain. |
| **HMAC-SHA256 with a server-side key** | Accepted: a leaked table alone is useless without the key, which lives only in the environment; one HMAC is microseconds. |

The key is a dedicated variable, `ACCOUNT_CODE_SECRET` (Base64, at least 256 bits, one line), not the
JWT key: a compromise or a rotation of one must not touch the other. The application refuses to
start without it (`AccountCodeProperties`, same fail-fast rules as `JwtProperties`). Changing the
key invalidates codes not yet used; they live 15 minutes, so that is acceptable.

**3. Purpose and user binding.** The HMAC input is `purpose|userId|code`. A reset code cannot verify
an email and a code of one user never matches another user's row, even if the same six digits occur.
Comparison uses `MessageDigest.isEqual` (constant time).

**4. Limits.** Live for 15 minutes; 5 wrong attempts, then the code is dead; single use (`used_at`);
at most one live code per (user, purpose), a new request replaces the old one and resets the attempts;
resend cooldown of 60 seconds and at most 5 sends per hour per (user, purpose). All are properties
with these defaults (`app.account-code.*`).

**5. One row per (user, purpose), counters in the database.** `account_codes` has a unique
`(user_id, purpose)` constraint; the row also stores `attempts`, `used_at`, `window_started_at` and
`sends_in_window`. Reasons:

- The limits survive restarts and work with several API instances (an in-memory limiter would not).
- Every issue and every check first locks the row (`SELECT ... FOR UPDATE`), the same idea as the
  family row of ADR 0008: two parallel guesses cannot both read `attempts = 4`, and two parallel
  checks of the right code cannot both succeed.
- The first insert of a pair uses `INSERT ... ON CONFLICT DO NOTHING`: when two first requests race,
  the loser inserts 0 rows and is answered like a throttled request, with no exception that would
  poison the transaction.
- The unique index also serves the foreign key lookup, so there is no separate `idx_` index.

**6. Failed attempts are committed.** `consume` never throws for a bad code: it increments `attempts`
and returns `false`, so the caller's transaction commits the increment. (If it threw and the
transaction rolled back, an attacker would get unlimited guesses.) Callers must not roll back on `false`.

**7. A failure budget that survives reissue.** Without it, the limits above still allow 5 attempts
per code x 5 codes per hour x 24 h = 600 guesses a day against one account (a new code resets
`attempts`). So every wrong guess (malformed or `null` included) also counts in `failed_in_window`,
kept in the same row and **not** reset by a new code. The window is fixed, opened by the first failure
and closed after 24 hours (`app.account-code.failure-window`), or earlier by a successful `consume`.
While `failed_in_window >= max-failures-per-day` (default 10), `consume` returns `false` without
comparing and `issue` returns empty. A guess against a code that is already dead (expired, used, 5
attempts) is not counted: it cannot succeed, so it needs no budget.

**8. The two keys must differ.** The application refuses to start when the decoded
`ACCOUNT_CODE_SECRET` equals the decoded `JWT_SECRET` (`DistinctSecretsValidator`, constant-time
compare, the message quotes neither).

**9. The resend window** is fixed, opened by the first send and reset after one hour, not a sliding
window: simpler to store and to reason about, and enough against abuse.

**10. Endpoints (step 2): limits and answers that do not leak.**

- Forgot password always answers `202`; unknown email, a refused code and a failed email look the same.
- Every confirm failure is one `400 invalid-code` (wrong, expired, used, exhausted, replaced, other
  purpose, spent budget, unknown email, per-email limit). Failed attempts are committed: the services
  run `consume` inside a `TransactionTemplate`, return a boolean and throw only after the commit.
- **Per IP** (in memory, `app.rate-limit.*`, TCP peer address, `X-Forwarded-For` never trusted):
  10 requests/hour on `password-reset`, 20/hour on `password-reset/confirm`; past it `429` +
  `Retry-After`. **Per email** (in memory, key = SHA-256 of the lowercase email): 5/hour on the
  request, 20/hour on the confirm. A per-email limit is **silent** (request: `202` without sending;
  confirm: `invalid-code`) and never `429`: the per-IP `429` depends only on the caller's address, so
  it reveals nothing about accounts, while a per-email `429` would reward an enumerator with a signal.
  Per-email confirm answers `invalid-code`, not `429`, because that is exactly what an unknown email
  gets. Cost: an attacker can burn a victim's per-email hour with 20 requests; the failure budget
  already allows a longer lockout (point 7), so this adds no new capability.
- **Security event:** the guess that spends a failure budget logs one `WARN` with the user id and the
  purpose (never the email or a code), so a repeated lockout can be noticed.
- The reset locks the user row, so two parallel confirms of one code succeed once, and a login that
  verified the old password re-checks the hash under the same lock before starting a session.
  Resetting also revokes every session of the user and marks the email verified.

## Consequences

- A leaked database does not allow forging codes; a leaked key plus the database does, which is why
  the key is separate from the JWT key and only in the environment.
- Five attempts over 15 minutes bound a guess at 5 in a million per code, and 5 sends per hour bound
  how many fresh codes an attacker can ask for. Those two alone allowed 600 guesses a day (about 0.06%
  a day, 20% a year per account); the failure budget caps it at 10 a day: 10 in a million, about 0.4%
  a year per account, however many codes are requested.
- A legitimate user who mistypes is rarely affected (10 wrong guesses in 24 h on one account). An
  attacker who knows the email can burn the budget (about 12 requests) and block password recovery
  for that account for 24 h, and **renew the block every day for as long as they repeat it**. Login
  with the current password keeps working and nothing is exposed. Accepted as the price of a bounded
  guess rate; the per-IP and per-email limits of the endpoints (point 10) and Phase 4 reduce it, and
  logging one security event when a budget is exhausted makes a repeated lockout detectable.
- A user who requests codes quickly sees "wait" behavior decided by the endpoints (point 10); the
  service only says "empty".
- Account enumeration is the endpoints' concern: forgot-password always answers `202`.
- The in-memory limits are per API instance and, behind a reverse proxy, per proxy address; shared
  counters and trusted proxy headers are Phase 4.

## Alternatives rejected

- Longer or alphanumeric codes: worse to type, and not needed given the limits.
- Magic links: they put a token in a URL (api/CLAUDE.md rule 10) and need a web page; the app has
  a code field instead.
- Storing the counters in memory or Redis: a new moving part for no gain at this scale.
