# Code notes: email

The long explanations behind `shared/email/`
(`api/src/main/java/com/yulehohenfeld/snapledger/shared/email/`). The decisions are in
[ADR 0013](../decisions/0013-email-sending.md).

**PT:** As explicações longas por trás de `shared/email/`. As decisões estão na
[ADR 0013](../decisions/0013-email-sending.md).

## EmailMessage

A record: recipient, subject, text part, HTML part. Its `toString` masks the recipient and omits both
bodies: a record's default `toString` prints every field, and the bodies carry account codes
(api/CLAUDE.md rules 8 and 11). The subject is printed because it never contains personal data.

**PT:** Um record. O `toString` mascara o destinatário e omite os dois corpos: o `toString` padrão de
um record imprime todos os campos, e os corpos levam códigos de conta.

## EmailSender

The port. One method; failure is an unchecked exception. Features depend on this interface only, so a
real provider is a new class implementing it.

**PT:** A porta. Um método; a falha é uma exceção não verificada. As features dependem só desta
interface, então um provedor real é uma classe nova que a implementa.

## SmtpEmailSender

Adapter over `JavaMailSender`: one `multipart/alternative` message (text and HTML), UTF-8, From taken
from `app.mail.from`. If building the message fails, the `MessagingException` is not kept as a cause: an
address error message quotes the recipient. No tracking pixel, no links, no external images.

**PT:** Adaptador sobre o `JavaMailSender`: uma mensagem multipart (texto e HTML), UTF-8, remetente de
`app.mail.from`. Se montar a mensagem falhar, a `MessagingException` não é guardada como causa: a
mensagem de erro de endereço cita o destinatário.

## EmailProperties

`app.mail.from`, blank stops startup. `MAIL_FROM=` empty in `.env` would override the default with an
empty string (a present property wins over a `${X:default}`), so `.env.example` carries a real value.

**PT:** `app.mail.from`; vazio impede a subida. Um `MAIL_FROM=` vazio no `.env` sobrescreveria o padrão
com texto vazio, então o `.env.example` traz um valor real.

## MailExecutorConfig

`ThreadPoolTaskExecutor`: core 1, max 2, queue 100. Spring starts threads above the core only when the
queue is full, so in practice it is one thread until 100 messages wait; beyond that, the default
`AbortPolicy` rejects, and `MailDispatcher` logs it. Shutdown waits up to 10 s for queued mail.

**PT:** O Spring só cria threads acima do core quando a fila enche, então na prática é uma thread até
100 mensagens esperarem; depois disso a `AbortPolicy` padrão rejeita e o `MailDispatcher` registra.

## MailDispatcher

`sendAfterCommit(message)`: with an active transaction it registers a `TransactionSynchronization`
whose `afterCommit` submits to the executor (a rollback sends nothing); with none it submits at once.
It catches `RuntimeException` at every step (registration, submit, delivery) and logs one line,
`Email not sent: <exception class>`, never the message (a `MailSendException` text can quote the
recipient or a server reply). The caller never learns of the failure.

**PT:** Com transação ativa registra um `TransactionSynchronization` cujo `afterCommit` envia ao
executor (um rollback não envia nada); sem transação, envia na hora. Captura `RuntimeException` em todo
passo e registra uma linha só com a classe da exceção.

## mail-loggers

The mail library (Angus Mail, the Jakarta Mail implementation) logs the SMTP conversation under the
package of the speaking class (`org.eclipse.angus.mail.smtp`, `.protocol`): `RCPT TO:<...>` at
`DEBUG`, headers and body at `TRACE`. `logback-spring.xml` pins `org.eclipse.angus.mail` and
`jakarta.mail` to `INFO`, so raising a grandparent (`logging.level.org=TRACE`) does not reach them.
`MailLoggerPinIntegrationTest` drives the real library against an in-process SMTP server
(`FakeSmtpServer`) with a positive control (pin removed: the recipient appears), so a library upgrade
that renames the logger fails a test. `mail.debug` is never set; it would print to `System.out`
regardless of any logger.

**PT:** A biblioteca registra a conversa SMTP sob o pacote da classe que fala: `RCPT TO` em `DEBUG`,
cabeçalhos e corpo em `TRACE`. O `logback-spring.xml` fixa `org.eclipse.angus.mail` e `jakarta.mail` em
`INFO`. O teste usa a biblioteca real contra um servidor SMTP no processo, com controle positivo. O
`mail.debug` nunca é ligado; ele imprimiria no `System.out` independentemente de qualquer logger.
