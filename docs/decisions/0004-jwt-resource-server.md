# 0004. Validate JWTs with Spring's OAuth2 Resource Server

- Status: Accepted
- Date: 2026-11-10

## Context

Every protected request carries `Authorization: Bearer <accessToken>` ([ADR 0002](0002-refresh-token-rotation.md)).
The API must reject missing, malformed, tampered or expired tokens, and turn a valid token
into the authenticated user for the rest of the request.

A common approach is to add a JWT library (for example jjwt) and write a custom
`OncePerRequestFilter` that parses the header, validates the token and fills the
`SecurityContext`. Hand-written filters are a frequent source of security bugs, for
example writing a `403` to the response but still calling `chain.doFilter(...)`, catching
parsing exceptions too broadly, or forgetting to check expiry. They are also custom code
that has to be tested and maintained.

## Decision

Use `spring-boot-starter-oauth2-resource-server`. The API issues its own tokens; this
module only **validates Bearer tokens** (RFC 6750). Despite the name, we do not implement
OAuth2 login flows or run an authorization server.

- **Signing**: HS256 with a secret from the `JWT_SECRET` environment variable (base64,
  at least 256 bits). The application **refuses to start** if it is missing or too short
  (`@ConfigurationProperties` + `@Validated`).
- **Issuing**: `NimbusJwtEncoder` (from the same Spring Security JOSE module) creates the
  access token in the auth service with claims `sub` (user UUID), `iss`, `iat` and `exp`.
- **Validating**: a `NimbusJwtDecoder` bean with the same secret, plus validators for
  `exp` (with a small clock skew) and `iss`. Registered with
  `http.oauth2ResourceServer(o -> o.jwt(...))`.
- **Current user**: controllers receive `@AuthenticationPrincipal Jwt jwt` (or a small
  `CurrentUser` resolver) and read the user id from `sub`. No endpoint accepts a user
  id from the body, query or path.
- **Errors**: the authentication entry point and the access-denied handler are customized
  to return RFC 9457 ProblemDetail (`401 unauthorized` with `WWW-Authenticate: Bearer`),
  the same format as every other error.
- **Session policy**: `SessionCreationPolicy.STATELESS`. CSRF is disabled for the API
  because it does not use cookies for auth.

## Consequences

- Validation, error signalling and integration with method security come from code that
  is maintained and reviewed by the Spring Security team.
- Less code of our own: configuration plus one encoder service.
- Controllers stay unaware of tokens; they only see the authenticated principal.
- HS256 uses one shared secret for signing and verifying. That is fine with a single
  service. If more services ever need to verify tokens, migrate to RS256/ES256 with a
  public key (or a JWKS endpoint) in a new ADR. The decoder change is small.
- Rotating `JWT_SECRET` invalidates all access tokens (users refresh transparently, since
  refresh tokens are not JWTs).

## Alternatives considered

- **jjwt + custom filter**: full control, but more code, more tests and a well-known class
  of filter bugs. Rejected.
- **Full authorization server** (Spring Authorization Server, Keycloak, Auth0): the right
  choice for many clients, third-party apps or SSO, but overkill for one first-party app.
  It adds infrastructure and complexity that the project does not need now. Rejected for v1.
- **Opaque access tokens with introspection on every request**: easy revocation, but a
  database hit on every call, which defeats the short-lived stateless access token. Rejected.

## References

- [Spring Security: OAuth 2.0 Resource Server JWT](https://docs.spring.io/spring-security/reference/servlet/oauth2/resource-server/jwt.html)
- [RFC 6750: Bearer Token Usage](https://www.rfc-editor.org/rfc/rfc6750)
- [RFC 8725: JWT Best Current Practices](https://www.rfc-editor.org/rfc/rfc8725)
