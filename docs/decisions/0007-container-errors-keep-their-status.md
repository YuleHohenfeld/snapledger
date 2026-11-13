# 0007. Container errors keep their real status and the ProblemDetail format

- Status: Accepted
- Date: 2026-11-12
- Refines: [ADR 0004](0004-jwt-resource-server.md), [ADR 0005](0005-auth-endpoints-separate-filter-chain.md)

## Context

Most errors are raised inside Spring MVC and answered by `GlobalExceptionHandler`. Some are
not: the servlet container (Tomcat) handles them by **forwarding the request internally to
`/error`**. This happens when:

- Spring Security's firewall rejects a dangerous URL (for example a path with `;`, `//` or an
  encoded `.`, used in path-traversal tricks), or
- an exception escapes MVC entirely (for example an `Error`, or a failure while writing the response).

That internal forward is a new pass through the security filter chain, with dispatcher type
`ERROR`. `/error` is not under `/api/v1/auth/**`, so chain 2 handles it and requires a token:

- an **anonymous** caller gets `401 unauthorized` with `WWW-Authenticate: Bearer`, hiding the
  real error;
- an **authenticated** caller gets Spring Boot's default error JSON, not our ProblemDetail.

The first case is the dangerous one for the app: its interceptor reacts to `401` by refreshing
the token and, if that fails, wiping the session. A **server error could log the user out**.

## Decision

1. Chain 2 permits a request only when **both** hold: dispatcher type `ERROR` **and** path
   `${server.error.path:/error}` (`AndRequestMatcher` of `DispatcherTypeRequestMatcher(ERROR)` and
   a `PathPatternRequestMatcher` for the error path, read from the same property the controller
   is mapped to). Only the container can produce an `ERROR` dispatch. An `ERROR` dispatch to any
   other path (a custom error page, a future forward) stays `authenticated()`. A client calling
   `GET /error` directly makes a normal `REQUEST` dispatch, which also stays `authenticated()`.
2. `/error` is owned by our `ProblemErrorController` (replacing Boot's `BasicErrorController`).
   It answers with the **real status** in the contract ProblemDetail format, through
   `ProblemFactory`, always as `application/problem+json`, never with `WWW-Authenticate`, and
   always with `X-Content-Type-Options: nosniff` and `Cache-Control: no-store`:
   - **any 5xx** is answered as `500 internal-error` with `errorId` (the original 5xx status is
     not kept: the client only needs "server failure" plus the id; `503`, `502`... are never
     exposed with a different shape);
   - other statuses with a contract slug use it (`400 validation-error`, `401 unauthorized`,
     `403 forbidden`, `404 not-found`, `405`, `406`, `415`); `401` still never carries
     `WWW-Authenticate`, which only the security entry point sends;
   - statuses without a slug (`413`, `414`, `431`...) use `type: about:blank` and the standard
     reason phrase as `title` (RFC 9457 §4.2.1). `GlobalExceptionHandler` uses the same rule for
     framework errors (`ProblemFactory.forFrameworkStatus`), so a status gets the same body
     whichever of them answers;
   - database errors are logged masked, with the same rule as `GlobalExceptionHandler`
     (shared code, one place: `InternalErrors`);
   - it must never throw: an error inside an error dispatch has no further fallback.
     `InternalErrors` bounds its exception traversal (1,024 nodes; a bigger graph is masked) and
     absorbs any failure while inspecting or logging, except an `OutOfMemoryError`,
     `InternalError` or `UnknownError` (JVM-wide failures).
3. Requests rejected by the firewall are answered with `400` (`HttpStatusRequestRejectedHandler`),
   which then flows through point 2.
4. Chain 1 needs no change: a forward to `/error` never matches `/api/v1/auth/**`.
5. Database values must never reach any log, including loggers we do not own:
   - pgjdbc runs with `logServerErrorDetail=false`
     (`spring.datasource.hikari.data-source-properties.logServerErrorDetail`), so the server's
     `Detail:` line (`Key (email)=(...) already exists`) is never copied into an exception message;
   - `logback-spring.xml` turns off Tomcat's wrapper logger
     `org.apache.catalina.core.ContainerBase.[Tomcat].[localhost].[/].[dispatcherServlet]`, which
     logs every exception escaping the filter chain unmasked. The same exception is logged by
     `InternalErrors` at `/error`, with its `errorId`. A test reads the logger name from the
     running Tomcat (context and dispatcher servlet), so a new context path or servlet name fails
     it instead of silently bringing the unmasked copy back;
   - `logback-spring.xml` also turns off Hibernate's SQL error logger `org.hibernate.orm.jdbc.error`
     (Hibernate 7; older versions used `SqlExceptionHelper`). PostgreSQL puts some values in the
     **primary** message, which `logServerErrorDetail=false` does not remove (22P02
     `invalid input syntax for type uuid: "..."`). Unexpected failures are still logged by
     `InternalErrors`, masked; handled ones (a `409`) need no driver line. Its SQL warnings are
     silenced too;
   - `logback-spring.xml` pins Spring's
     `org.springframework.web.servlet.mvc.method.annotation.ExceptionHandlerExceptionResolver` to
     `INFO`. At `DEBUG` it logs `Resolved [<exception toString>]`, unmasked, for every exception
     `GlobalExceptionHandler` resolves, so a troubleshooting setting such as
     `logging.level.org.springframework.web=DEBUG` would print driver messages. Spring 7 logs under
     the concrete resolver class; a test with a positive control proves the name. Setting that
     exact logger to `DEBUG` explicitly still brings the line back.
   - `logback-spring.xml` pins Spring's fallback resolver
     `org.springframework.web.servlet.mvc.support.DefaultHandlerExceptionResolver` to `ERROR`. It
     receives an exception only when one of our `@ExceptionHandler`s fails with something that is
     not a client disconnect, and then logs at `WARN` "Ignoring exception, response committed
     already: " + the exception's `toString` (or "Failure while trying to resolve exception"),
     unmasked and with any raw newline kept, which also allows log forging. It has no `ERROR`
     lines, so nothing useful is lost: `ExceptionHandlerExceptionResolver`'s "Failure in
     @ExceptionHandler" `WARN` still records the failed handler, and a `5xx` sent before commit
     still reaches `/error`. A test with a positive control proves the name.
   - `logback-spring.xml` pins Hibernate's binding logger `org.hibernate.orm.jdbc.bind` to `INFO`
     (added 2026-11-13). At `TRACE` it logs every bound value (`binding parameter (1:VARCHAR) <-
     [ana@example.com]`, password and token hashes included), so raising a parent such as
     `logging.level.org.hibernate=TRACE` to see SQL parameters would print them. A test with a
     positive control proves the name.
   - The five logger names above (Tomcat wrapper, Hibernate SQL errors, Hibernate bindings and the
     two resolvers) are each proven by a test, so an upgrade that renames one fails a test.
   - Residual risk, accepted: with `org.springframework.web` at `DEBUG`, `FrameworkServlet` logs
     `"Failed to complete request: " + cause` under the `DispatcherServlet` category for any
     failure that leaves MVC, so a database failure rethrown after commit (point 6) is printed
     there unmasked. `DispatcherServlet` is **not** pinned: it is the main troubleshooting logger
     of Spring MVC, and the leak needs both a committed response and a non-default log level,
     which no current endpoint produces. Revisit with the first streaming endpoint.
6. A failure that escapes **after the response is committed** is logged by
   `CommittedResponseFailureFilter` (highest precedence, `REQUEST` dispatch), through
   `InternalErrors` with the same masking and `responseCommitted=true`. Tomcat cannot forward a
   committed response, so it `INCLUDE`s `/error` instead: chain 2 denies the anonymous include
   (point 1 permits only `ERROR`) and the authenticated include did not log either, so with the
   wrapper logger off (point 5) the failure left no trace. The filter logs only when the response
   is committed and always rethrows; an uncommitted failure is logged once, at `/error`. The
   `errorId` of that line is never sent: there is no body left to carry it. The `permitAll` is
   **not** widened to `INCLUDE`: it would open `/error` to any future include and would not fix
   the authenticated case.
   - **Inside Spring MVC** (a controller that has streamed past the 8 KB buffer and then fails),
     the failure reaches `GlobalExceptionHandler` with the response committed. Both
     `handleUnexpected` and `handleExceptionInternal` check that first; without the check a
     ProblemDetail was glued to the end of the half-sent body and, for framework errors, the base
     class added a WARN with the exception's `toString`, unmasked.
     - The catch-all (`handleUnexpected`) **rethrows the same instance**, without logging. No other
       resolver knows it, so it leaves MVC, the filter logs it once (masked,
       `responseCommitted=true`) and Tomcat **aborts the connection**: the last chunk of the
       chunked body is never sent, so the client sees a broken response, not a complete one. The
       same instance keeps `ExceptionHandlerExceptionResolver` from adding its
       "Failure in @ExceptionHandler" WARN. Because Spring wraps it on the way out, the logged
       class is `jakarta.servlet.ServletException`; masking still looks at the whole graph.
     - A framework error (`handleExceptionInternal`) is **not** rethrown: every type that reaches
       it is also known to Spring's `DefaultHandlerExceptionResolver`, which, given the rethrown
       exception, resolved it with two unmasked WARNs ("Ignoring exception, response committed
       already: " + `toString`), let Tomcat end the response normally and left no `errorId` line
       at all (reproduced against a real Tomcat). It is logged once through
       `InternalErrors.logCommitted` and `null` is returned (handled, nothing written), so it never
       reaches the filter.
     - A client disconnect after commit is not rethrown either: one `DEBUG` line, `null` (point 7).
   - **Only synchronous endpoints are covered.** Boot registers a plain `Filter` bean for the
     `REQUEST` dispatch only. A failure in an `ASYNC` dispatch (`DeferredResult`, `Callable`,
     `StreamingResponseBody`, SSE) would pass the filter unseen. The first such endpoint must
     register the filter for `DispatcherType.ASYNC` too, through a `FilterRegistrationBean`, and
     add a committed-failure test for it. It must also add the committed-response check
     (`abortIfCommitted` + rethrow) to `handleApi` and `handleConstraintViolation`: today an
     `ApiException` or a method-validation failure thrown after commit would get its ProblemDetail glued to the half-sent body, which no current endpoint can cause:
     they all throw before anything is written.
7. A **client that goes away** (closed app, lost network, TCP reset) is not a server failure.
   `InternalErrors.isClientDisconnect` recognizes it **by type** as the failure itself or along
   its cause chain (Tomcat's `ClientAbortException`, Spring's `AsyncRequestNotUsableException`),
   never by message, and only when no database error is anywhere in the graph (causes and
   suppressed): a driver `Connection reset` stays a masked `ERROR`. Suppressed exceptions are not
   searched for a disconnect: one attached there (a `close()` that failed because the client was
   gone) is a side effect of the real failure, which stays an `ERROR`. It is logged as one `DEBUG`
   line (`Client disconnected errorId=... exception=...`, no message, no stack trace) by
   `handleUnexpected`, by the 5xx branch of `handleExceptionInternal` and by `logCommitted` (so by
   the filter too), and nothing is written. Before commit the handler still sets status `500`, so
   nothing that reads the status records the default `200`. `DEBUG`, not `INFO`:
   nobody can act on it and an anonymous client can repeat it at will, so at `ERROR` with a stack
   trace (about 100 lines each) it would drown real failures; Spring logs its own line for the
   same event at `DEBUG`. `java.io.EOFException` is left out on purpose: file and deserialization
   bugs throw it too.
   Spring 7 already turns a failed **write** inside MVC into `AsyncRequestNotUsableException` and
   answers it itself (the base handler, one `DEBUG` line of its own), so a reset while a
   controller streams never reached our code. What did reach it, as `ERROR` with a stack trace,
   is a reset while a controller **reads** the raw request body (a future upload). Both cases are
   tested against a real Tomcat.

## Consequences

- A server error is never disguised as "please log in", so the app never refreshes or logs out
  because of it.
- Every error the API can return now has the same shape, whether it comes from a controller,
  a security filter or the container.
- The "unknown route, anonymous caller → 401" rule in the contract is unchanged: that request
  is a `REQUEST` dispatch and is authenticated before routing.
- An authenticated client calling `GET /error` directly gets `404 not-found`: to it, `/error`
  is just a route that does not exist. An anonymous one gets `401 unauthorized` (point 1).
- Firewall and container error responses have **no CORS headers**: the firewall rejects the
  request before the CORS filter runs, and the CORS filter (a once-per-request filter) skips the
  `ERROR` dispatch, so a browser sees a CORS failure instead of the problem body. The mobile app
  is not affected.
  They do get `nosniff` and `no-store`, set by `ProblemErrorController` itself, because Spring
  Security's header filter skips `ERROR` dispatches.
- The catch-all `500` log line now comes from the logger category `InternalErrors` (it used to
  be `GlobalExceptionHandler`). Log searches and alerts must use the new category.
- Tomcat's wrapper logger is off. If the context path or the dispatcher servlet name ever
  changes, the logger name in `logback-spring.xml` must change too, or the unmasked copy returns
  (a test fails first, point 5). The wrapper logger is off as a whole, so its other messages (for
  example a servlet that fails to start) are silenced too; startup failures are still reported
  by Spring Boot.
- After a committed failure that escapes a filter, the client gets a truncated body and a closed
  connection, never a ProblemDetail. Tomcat's **host** logger (not the wrapper logger) then adds a
  line about the failed include ("Unable to handle the Spring Security Exception because the
  response is already committed" for an anonymous caller). It carries no value from the original
  failure and is left on: it is the only Tomcat signal that an include failed.
- After a committed failure **inside MVC** that reaches the catch-all, the connection is aborted
  like a failure that escapes a filter (point 6): the client gets the status already sent, the
  bytes written before the failure and no last chunk, so a client library reports an error.
- After a committed **framework** error inside MVC (for example `HttpMessageNotWritableException`
  when serialization fails mid-body) the exception is handled (point 6), so Tomcat ends the
  response normally: the client gets the status already sent and the bytes written before the
  failure, with no error marker. A JSON client fails to parse the cut body; a client of a future
  file download could not tell a cut file from a whole one. That endpoint will need its own
  integrity signal (for example a declared `Content-Length` or a checksum).
- Container paths need a **real server** (`@SpringBootTest` with a random port) for the forward,
  the firewall and Tomcat's logging; MockMvc does not perform error dispatches. The controller's
  body rules are covered with MockMvc by building the `ERROR` dispatch by hand.

## Alternatives considered

- **Disable security for error dispatches** (`spring.security.filter.dispatcher-types` without
  `ERROR`): with no chain on the `ERROR` dispatch, nothing restricts which path an `ERROR`
  dispatch may reach, so any future forward or custom error page would be served without
  authentication. (Security headers are not the reason: the header filter already skips `ERROR`
  dispatches, so `ProblemErrorController` sets them itself.) Rejected.
- **Customize only `ErrorAttributes`**: keeps Boot's JSON shape and content negotiation, so the
  body would still not be our ProblemDetail. Rejected.
- **Leave Boot's default `/error`**: two error formats and the false `401`. Rejected.
