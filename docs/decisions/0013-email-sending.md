# 0013. Email sending: a port, an SMTP adapter, async after commit, best effort

- Status: Accepted
- Date: 2026-11-17

## Context

Account codes (ADR 0012) travel by email. Sending email is slow (a network round trip, sometimes
seconds), can fail for reasons the user cannot fix, and its content is sensitive (a code and an
address). The API has no email provider yet and no production target, but the code should not
change when one is chosen.

## Decision

1. **A port, `EmailSender`, in `shared/email/`.** Features build an `EmailMessage` and never see SMTP.
   The only implementation now is `SmtpEmailSender`, on Spring's `JavaMailSender`. A real provider
   (SES, SendGrid...) later is a new adapter, either SMTP settings or an API client, with no change in
   `accountcode/`.
2. **SMTP to Mailpit locally and in demos.** `docker-compose.yml` runs Mailpit (pinned tag): it accepts
   every message and delivers nothing outside; the inbox is at `http://localhost:8025`, SMTP at `1025`,
   both bound to `127.0.0.1`. Host, port and credentials come from `MAIL_*` variables.
3. **Asynchronous, after commit, on a bounded executor.** `MailDispatcher.sendAfterCommit` registers
   the send for `afterCommit` of the caller's transaction (or sends at once without one) and runs it on
   a `ThreadPoolTaskExecutor` (1 to 2 threads, queue of 100).
   - After commit: a rolled-back request must not send a code that was never stored.
   - Async: the HTTP response does not wait for SMTP, so response time does not reveal whether an
     account exists (forgot password must answer the same for everyone).
   - Bounded: a stalled SMTP server cannot create unbounded threads or memory; a full queue rejects.
4. **Best effort, never failing the caller.** The dispatcher catches everything: a rejected task or a
   mail exception logs one line with the **exception class only** and the request goes on. The
   user can ask for another code (limits of ADR 0012). SMTP timeouts are 5 seconds.
5. **Nothing sensitive in logs.** Never the recipient, subject details or body: `EmailMessage.toString`
   masks the address and omits the bodies, the dispatcher logs the class, and the mail library's own
   loggers are pinned to `INFO` in `logback-spring.xml` (SMTP debug prints `RCPT TO` and bodies),
   proven by a test with a positive control. `mail.debug` is never enabled.
6. **No tracking, no external content.** Messages are plain text plus a simple HTML copy: no links,
   no images, no tracking pixels.

## Consequences

- Delivery is not guaranteed and not reported: a lost email looks like a code that never arrives; the
  user asks again.
- A process crash between commit and send loses the email (no outbox). Acceptable for 15-minute codes;
  an outbox table is the next step if delivery must be guaranteed.
- Production needs a real SMTP relay or a new adapter and a sender domain (SPF/DKIM) before launch.

## Alternatives rejected

- Sending inside the request thread: slow, and leaks account existence through timing.
- `@Async` without a bounded executor: Spring's default would be unbounded or shared.
- A transactional outbox now: more tables and a poller for a feature whose emails expire in minutes.
