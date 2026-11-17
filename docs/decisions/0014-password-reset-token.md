# 0014. Password reset in two steps: verify the code, then confirm with a reset token

- Status: Accepted (refines [ADR 0012](0012-account-codes.md) point on reset confirmation)
- Date: 2026-11-17

## Context

ADR 0012 had one `confirm {email, code, newPassword}`. The app wants to show the code as correct
(green) before asking for the new password, so the code must be checked on its own, and the
password step needs a proof that the check happened.

## Decision

1. `POST /auth/password-reset/verify {email, code}` checks the code, **consumes it** and answers
   `200 {resetToken, expiresIn: 600}`. Every refusal is the same `400 invalid-code`; a wrong code is
   committed (attempt and failure budget) before the 400 (the GATE of ADR 0012, same return-then-throw).
2. `POST /auth/password-reset/confirm {resetToken, newPassword}` changes the password, marks the
   email verified, revokes every session (`revokeAllOf` last), spends the token and sends the
   "password changed" email after commit. A bad token is `400 invalid-reset-token` (new slug), so
   the app can send the user back to the start. The old `{email, code, newPassword}` confirm is gone.
3. The token is 256 bits from `SecureRandom`, base64url without padding, TTL 10 minutes, single use,
   one live grant per user (a new verify replaces it). Only its **SHA-256 hex** is stored, in the new
   table `password_reset_grants` (V5), unique on `user_id` and on `token_hash`.
4. SHA-256 and not HMAC: the token has 256 bits of entropy, so there is nothing to brute-force and
   no dictionary to precompute; HMAC (used for the 6-digit code, 10^6 possibilities) would add a
   secret to manage for no gain. Same reasoning as refresh tokens (ADR 0002).
5. Limits: verify has the old confirm limits (per IP 20/h with `429`, per email 20/h silent as
   `invalid-code`); confirm has per IP 20/h only (the token is the credential, there is no email to
   key on).
6. Lock order (extends the documented one): **user, account_code, grant, families, tokens**.
   Verify locks user, then account_code, then upserts the grant. Confirm finds the user id by token
   hash **without a lock**, locks the user, then locks the grant by hash and re-checks it (it may
   have been replaced meanwhile), then `revokeAllOf` (families, tokens). Every path takes the locks
   in the same order, so no cycle exists; login, rotate and refresh never touch grants.
7. Unknown email on verify computes an HMAC for a fixed dummy user id, so its cost is close to a
   known one. Residual differences: a known email also takes row locks, an extra SELECT and an
   upsert; not claimed to be constant time.

## Consequences

- The app gets the green step, and a leaked 6-digit code alone no longer sets a password after
  verify: the attacker would need the token too. A stolen token is worth 10 minutes and one use.
- The token lookup by hash is a credential lookup: an index on a unique hash column, no secret
  compared in application code.
- One more table, one more slug (`invalid-reset-token`, 17 slugs), one more bucket.
- Two round trips instead of one; verify and confirm are separately retryable only before use.
- Access tokens issued before the reset stay valid up to 15 min (unchanged).

## Alternatives considered

- Keep one confirm and add a read-only "check" endpoint: rejected, a check that does not consume
  the code lets the app learn the code without spending a guess budget differently, and the final
  confirm would re-verify the code anyway (two sources of truth).
- A signed JWT as reset token (ADR 0006 reserved an audience for it): rejected, it cannot be made
  single use or replaced without server state, which we need anyway.
- Store the token in `account_codes`: rejected, it mixes a 10-minute credential with the code's
  resend and failure counters and its purpose-unique row.
