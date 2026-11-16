# 0011. App session lifecycle: where tokens live, how they refresh, when the session ends

- Status: Accepted
- Date: 2026-11-16

## Context

[ADR 0010](0010-app-architecture-mvvmc-provider.md) chose Dio with an `AuthInterceptor` and
`flutter_secure_storage`, but left the session's behavior open. The contract
([Auth](../api-contract.md#auth)) gives the constraints: a 15-minute access token; a 30-day
refresh token that **rotates** on every use; reuse of an old refresh token revokes the whole
session family ([ADR 0002](0002-refresh-token-rotation.md)); `401 invalid-refresh-token` must wipe
the session; a `500` on refresh leaves the token untouched and "the app may retry"
([ADR 0009](0009-password-hashing-and-database-lock-timeout.md)); `/auth/*` endpoints are public
and ignore `Authorization` ([ADR 0005](0005-auth-endpoints-separate-filter-chain.md)).

Rotation makes mistakes expensive: two refreshes in parallel, or losing the newest refresh token,
log the user out; refreshing the wrong way can make the server revoke a healthy session. Mobile
apps also go offline, get killed mid-request and restart cold.

## Decision

1. **Access token in memory only; refresh token persisted** in the device keychain / keystore
   through `SecureStore` (`TokenStore`). Passwords are never stored.
2. **Cold start = one refresh** (`SessionNotifier.restore`): success → signed in; no token or
   `invalid-refresh-token` → signed out; anything else → state stays `unknown` with
   `restoreFailed`, the **token is kept**, and the user can retry.
3. **Only `401 invalid-refresh-token` (or no stored token) ends the session.** A refresh that fails
   with `500`, another `4xx`, a timeout, no network, a malformed body or a storage error keeps the
   session; the original error goes to the caller.
4. **One refresh at a time**: `ApiSessionRefresher` keeps a single-flight future shared by the
   interceptor and the cold start; it uses its own Dio without the interceptor. It returns a sealed
   `RefreshOutcome` (`Refreshed`, `SessionEnded`, `TemporaryFailure`); on `SessionEnded` it has
   already cleared the `TokenStore` itself, and both callers switch on the outcome exhaustively.
5. **New tokens are persisted before they are used**, and only if no wipe or sign-in happened
   since the refresh started (an **epoch** counter incremented by every wipe and every sign-in). A
   refresh overtaken that way changes nothing and reports `TemporaryFailure`.
6. **Interceptor rules**: attach the token only to the API's own origin (scheme, host and port of
   `API_BASE_URL`) under `/api/v1/`, never to `/auth/*` and never to a foreign absolute URL, and
   refresh only for those requests; refresh only on `401 unauthorized`; a request sent with an
   older token retries without refreshing; each request retries **once**; a retried request
   answered `401` again wipes the session. Dio never follows redirects: a `3xx` is a failure.
7. **Logout** calls `POST /auth/logout` best effort (5 s timeout) and then wipes locally regardless.
8. **Storage options**: iOS Keychain accessibility `first_unlock_this_device` (no iCloud sync, not
   restored to another device); Android uses the `flutter_secure_storage` 11.x defaults
   (Keystore-wrapped AES-GCM, `resetOnError: true`); a locked iOS keychain is treated as a
   temporary failure, any other unreadable entry is deleted.

## Consequences

- Every cold start costs one `POST /auth/refresh` before the first screen with data, and needs
  network to leave the splash screen. In exchange no access token ever rests on disk.
- Offline at start does not log the user out: the splash shows "try again" (step 3 of the auth
  feature implements the screen).
- A crash between the server's rotation and the local write loses the session (the user logs in
  again). This is inherent to rotation; persisting first keeps the window as small as possible.
- If the device storage cannot save the rotated token after a `200` refresh, the next refresh sends
  the already-rotated token; the server records it as **reuse** (an honest storage failure, not
  theft), revokes the family and answers `invalid-refresh-token`, so the session ends cleanly
  instead of looping.
- If the keychain delete fails on sign-out or wipe, the app is signed out at once (memory cleared,
  epoch moved) and `TokenStore` remembers in memory that the delete is pending: every later read
  retries it and returns nothing. **Residual risk**: if the app is killed before a retry succeeds,
  the next cold start finds the old token and restores the session the user had left, unless the
  server already revoked it (logout revokes first, so both the revoke and the delete must fail).
- Session logic is concentrated in `core/api/` and `core/session/`, which are on the
  `security-reviewer`'s mandatory list.
- **Open item**: Android Auto Backup is on by default (`android:allowBackup` is not set). The
  keystore key is not backed up, so a restored copy cannot be decrypted and `resetOnError` erases
  it, but excluding the secure storage file from backup (or `allowBackup="false"`) is cleaner. It is
  a platform config change, to be decided with the `security-reviewer` in step 3 of the auth feature,
  before the first Android release (tracked in the roadmap).

## Alternatives considered

- **Persist the access token too**: one request less at cold start, but a second credential at
  rest and stale-token `401`s on every start after 15 minutes anyway. Rejected.
- **Wipe on any refresh failure**: simpler, but a `500` from a busy session row (ADR 0009) or a
  subway tunnel would log users out. Rejected; the contract explicitly allows retrying.
- **Dio `QueuedInterceptor`**: also yields one refresh, but serializes every unrelated error behind
  it. Rejected in favor of a shared future.
- **Refresh proactively before `expiresIn`** with a timer: fewer `401`s, but timers on mobile are
  unreliable (app suspended) and it still needs the reactive path. May be added later on top of
  this design.
- **Refresher calling `SessionNotifier.wipe()` directly**: creates a construction cycle (session →
  refresher → session). The refresher clears the `TokenStore` and returns `SessionEnded`; its
  callers move the session state.
- **Refresher returning a nullable token**, callers inferring "session ended" from a moved epoch and
  an empty access token: the first version did this, and the inference was duplicated in the
  interceptor and the cold start, easy to get subtly different. Replaced by the sealed outcome.
- **`shared_preferences` or a file for the refresh token**: plain text at rest. Rejected (ADR 0010).

## References

- [RFC 9700: OAuth 2.0 Security Best Current Practice](https://www.rfc-editor.org/rfc/rfc9700), refresh token rotation
- [OWASP MASVS-STORAGE and MASVS-AUTH](https://mas.owasp.org/MASVS/)
- [Apple: Keychain item accessibility](https://developer.apple.com/documentation/security/ksecattraccessibleafterfirstunlockthisdeviceonly)
- Code notes: [`app-core.md`](../code-notes/app-core.md)
