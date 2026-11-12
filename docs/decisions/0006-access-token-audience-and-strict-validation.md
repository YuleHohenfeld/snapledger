# 0006. Access tokens are audience-bound and strictly validated

- Status: Accepted
- Date: 2026-11-11
- Refines: [ADR 0004](0004-jwt-resource-server.md)

## Context

ADR 0004 validates access tokens with Spring's OAuth2 Resource Server using the default
validators: signature (HS256), issuer (`iss`) and expiry (`exp`) with a 60-second clock skew.
The security review of the first increment found three weaknesses in that default:

1. **Token confusion.** The API signs JWTs with one key and checks only signature, issuer and
   expiry. If a future feature signs **another kind** of JWT with the same key (for example a
   password-reset or email-verification link with `sub = <userId>`), anyone who obtains that
   link could send it as `Authorization: Bearer ...` and it would be accepted as a full access
   token. Nothing in the token says what it is **for**.
2. **Missing claims pass.** A correctly signed token without `exp` may be treated as never
   expiring, and a token whose `sub` is missing or not a UUID passes the filter and fails later
   (a `500` in the controller instead of a `401` at the door). Only someone holding the key can
   create such tokens, but the shape of a credential should be checked where it enters.
3. **Generous clock skew.** The 60-second tolerance exists for systems where the issuer and the
   validator run on different machines with different clocks. Here the **same API** issues and
   validates, so the tolerance only extends the life of a stolen token (+60 s on a 15-minute
   token, about 7%). The default validator also reads the system clock instead of the injected
   `Clock`, so issuing and validating could disagree about "now".

## Decision

**Every access token carries an audience**, and the decoder accepts only tokens that pass
**all** of these validators (any failure → `401 unauthorized`, same generic body):

| Check | Rule |
|---|---|
| Signature | HS256 only (unchanged, ADR 0004) |
| `iss` | equals `app.security.jwt.issuer` (`snapledger-api`) |
| `aud` | contains `snapledger-api` (RFC 9068: access tokens are bound to the API that accepts them) |
| `sub` | present and a valid UUID |
| `exp`, `iat` | present |
| Expiry | `exp` checked with a **5-second** clock skew, using the injected `Clock` |

Rule for the future: **any other JWT** the system issues (reset links, email verification,
invitations...) must use a **different key** and a **different audience**. It must never be
signed with the access-token key or carry `aud = snapledger-api`.

## Consequences

- A token minted for another purpose cannot be replayed as an access token, even if the key
  were accidentally shared.
- Malformed tokens are rejected at the filter, so controllers and `@CurrentUserId` can trust
  that `sub` is a UUID.
- A stolen access token expires at most 5 seconds after its `exp`.
- Tests that sign tokens must include `aud`, `sub` (UUID), `iat` and `exp`; tests must also
  prove that tokens missing any of them are rejected.
- Token issuing (`AccessTokenService`, Increment 2) must set `aud`. Forgetting it would make
  every login produce unusable tokens, which the integration tests catch immediately.

## Alternatives considered

- **Keep the defaults**: simplest, but leaves the three weaknesses above. Rejected.
- **`typ: at+jwt` header instead of `aud`**: also defined by RFC 9068 and also effective, but
  `aud` is the more widely recognized claim and is validated with a standard
  `JwtClaimValidator`. Either would work; `aud` was chosen for clarity. Adding `typ` later is
  compatible.
- **Separate keys only, no audience**: protects against confusion only while every developer
  remembers to use a separate key. The audience check makes the API itself refuse foreign
  tokens. Rejected as the only defense; kept as the rule for future token types.
