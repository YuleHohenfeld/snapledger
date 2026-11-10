# 0002. Opaque refresh tokens with rotation and reuse detection

- Status: Accepted
- Date: 2026-11-10

## Context

The app needs sessions that last for weeks without asking for the password again, but a
stolen credential must stop working quickly and logout must really end the session.

A JWT access token is stateless: the server cannot revoke it before it expires. Making it
long-lived would make a leaked token valid for a long time. Making it short-lived without
a renewal mechanism would force frequent logins.

A common shortcut is to "refresh" by sending an identifier taken from the expired access
token plus some user attribute. That makes the refresh credential guessable or derivable,
and logout cannot revoke anything. We want to avoid it.

Constraints: a single PostgreSQL database, no Redis or other extra infrastructure.

## Decision

Use two tokens:

| Token | Format | Lifetime | Stored on server |
|---|---|---|---|
| Access token | JWT, HS256 ([ADR 0004](0004-jwt-resource-server.md)) | 15 minutes | No (stateless) |
| Refresh token | Opaque, 256 random bits, base64url | 30 days | Only its SHA-256 hash |

**Storage**: table `refresh_tokens`

| Column | Purpose |
|---|---|
| `id` UUID | Primary key |
| `user_id` UUID | Owner (FK to `users`) |
| `family_id` UUID | Groups every token born from the same login |
| `token_hash` CHAR(64), unique | SHA-256 (hex) of the token. The raw token is never stored |
| `expires_at` | Absolute expiry |
| `used_at` | Set when the token is rotated |
| `revoked_at` | Set on logout or reuse detection |
| `created_at` | Audit |

**Flows**

1. **Login / register**: create a new `family_id`, issue an access token and a refresh token.
2. **Refresh**: look up the token by hash.
   - Not found, expired or revoked: `401 invalid-refresh-token`.
   - Already used (**reuse**): revoke **every** token of the family, then `401 invalid-refresh-token`.
   - Valid: mark it used and issue a new pair in the **same family**, in one transaction.
     The "mark used" step is a conditional update (`... WHERE id = ? AND used_at IS NULL`).
     If it updates 0 rows, a concurrent request already rotated the token, which is treated as reuse.
3. **Logout**: revoke the family of the presented token. Always `204`.
4. **Cleanup**: expired rows are deleted by a scheduled job (Phase 4).

**Why SHA-256 and not bcrypt?** bcrypt is slow on purpose, to protect *low-entropy*
secrets like passwords against brute force. A 256-bit random token cannot be brute-forced,
so a fast hash is enough. It is also deterministic, so the token can be found by an indexed
`token_hash` lookup. If the database leaks, the hashes cannot be used as tokens.

**Client contract**: the app performs **at most one refresh at a time** (single-flight).
Other requests that get `401` wait for that refresh and retry with the new access token.
Without this, two parallel refreshes would trigger reuse detection and log the user out.

## Consequences

- A leaked refresh token works at most once. As soon as either party uses it again, the
  whole session dies. Detection, not prevention: rotation shrinks the attack window.
- Logout really ends the session server-side.
- An access token stays valid for up to 15 minutes after logout. This is accepted: it is
  the price of not hitting the database on every request.
- The client must implement single-flight refresh correctly, or users get logged out
  randomly. This is covered by tests in the app.
- One extra table and a cleanup job to maintain.
- Losing the device means losing the session: there is no "list of active sessions" in v1.

## Alternatives considered

- **Long-lived JWT only**: cannot be revoked; a leak lasts until expiry. Rejected.
- **Refresh token as a JWT**: self-contained, but still needs server state to revoke or
  detect reuse, so it has the same storage cost plus a bigger attack surface. Rejected.
- **Server-side sessions only (cookie + session store)**: simple for web, awkward for
  mobile clients, and needs a session store (Redis) or a DB hit on every request. Rejected for v1.
- **Rotation with a grace period** (accept the previous token for a few seconds): tolerates
  buggy clients but weakens reuse detection. Not needed because we control the client
  and enforce single-flight. Can be added later in a new ADR if needed.
- **Redis for tokens**: faster lookups, but a new piece of infrastructure for a load that
  PostgreSQL handles easily. Rejected.

## References

- [OAuth 2.0 Security Best Current Practice (RFC 9700), §4.14 Refresh Token Protection](https://www.rfc-editor.org/rfc/rfc9700)
- [OWASP Session Management Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Session_Management_Cheat_Sheet.html)
