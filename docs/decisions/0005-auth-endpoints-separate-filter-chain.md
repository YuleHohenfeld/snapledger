# 0005. Auth endpoints use a separate security filter chain

- Status: Accepted
- Date: 2026-11-11
- Refines: [ADR 0004](0004-jwt-resource-server.md)

## Context

Every request to the API passes through Spring Security's **filter chain**: an ordered list
of filters that run before the controller, like checkpoints at an airport. With the OAuth2
Resource Server (ADR 0004), one of those checkpoints is `BearerTokenAuthenticationFilter`.
When it sees an `Authorization: Bearer ...` header, it validates the token **immediately**.
If the token is expired or invalid, the request is rejected with `401` right there.

Authorization rules such as `permitAll()` are evaluated by a **later** filter. So a request
to a public route that carries an expired token is rejected before Spring ever learns that
the route was public.

This breaks the contract for the `/auth/*` endpoints:

- `POST /auth/logout` must work **with an expired access token** (the refresh token proves the session).
- `POST /auth/refresh` is called precisely **because** the access token expired.
- A client may keep sending a stale `Authorization` header by mistake.

We do not want correctness to depend on the client remembering to remove the header.

## Decision

Define **two** `SecurityFilterChain` beans, ordered with `@Order`:

| Order | Matches | Resource Server (JWT) | Rules |
|---|---|---|---|
| 1 | `/api/v1/auth/**` | **Not configured**: the `Authorization` header is ignored | `POST` on `register`, `login`, `refresh`, `logout` is `permitAll()`; anything else under `/auth/**` is denied |
| 2 | Everything else | Configured (ADR 0004) | Explicit public docs paths; everything else `authenticated()` |

Both chains share: stateless sessions, CSRF disabled (no cookie auth), the same CORS
configuration and the ProblemDetail entry point / access-denied handler.

The `/auth/*` endpoints authenticate the caller by what is **in the body** (email + password,
or the refresh token), never by the header.

## Consequences

- Logout and refresh behave as the contract says, regardless of what the client sends in headers.
- The intent is visible in code: public auth endpoints do not even have the JWT filter.
- Two chains to maintain. A new public endpoint outside `/auth/**` must be added to chain 2
  explicitly. A new endpoint under `/auth/**` is denied until it is listed in chain 1, so a
  mistake fails closed (denied), not open.
- Tests must cover: logout and refresh succeed with an expired or garbage `Authorization`
  header, and protected endpoints still reject it.
- Anyone tempted to "simplify" back to one chain must read this ADR first.

## Alternatives considered

- **One chain + custom `BearerTokenResolver` that returns no token for `/auth/**`**: works
  with less configuration, but hides the rule inside a resolver, and the path check is
  duplicated between the resolver and the matchers. Rejected for clarity.
- **One chain, and the client never sends the header to `/auth/*`**: the server's
  correctness would depend on every client version behaving. Rejected.
- **Make logout require a valid access token**: contradicts the contract. A user with an
  expired session could not log out cleanly. Rejected.
