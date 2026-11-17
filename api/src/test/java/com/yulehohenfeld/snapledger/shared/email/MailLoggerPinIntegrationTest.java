package com.yulehohenfeld.snapledger.shared.email;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.springframework.boot.logging.LogLevel;
import org.springframework.boot.logging.LoggingSystem;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.system.CapturedOutput;
import org.springframework.boot.test.system.OutputCaptureExtension;
import org.springframework.context.annotation.Import;
import org.springframework.mail.javamail.JavaMailSenderImpl;

import com.yulehohenfeld.snapledger.support.FakeSmtpServer;
import com.yulehohenfeld.snapledger.support.TestJwtSecret;
import com.yulehohenfeld.snapledger.support.TestcontainersConfiguration;

/**
 * logback-spring.xml pins the mail library's loggers to INFO, so raising them (or a parent) never
 * prints SMTP traffic: recipients and bodies carry personal data and account codes. Each pin has a
 * positive control, driven by the real library against an in-process SMTP server.
 *
 * <p>PT: O logback-spring.xml fixa os loggers da biblioteca de email em INFO, então subi-los (ou o
 * pai) nunca imprime o tráfego SMTP: destinatários e corpos levam dados pessoais e códigos de conta.
 * Cada fixação tem um controle positivo, com a biblioteca real contra um servidor SMTP no processo.
 * Notes: docs/code-notes/email.md#mail-loggers
 */
@ExtendWith(OutputCaptureExtension.class)
@SpringBootTest
@Import({TestcontainersConfiguration.class, TestJwtSecret.class})
class MailLoggerPinIntegrationTest {

    static final String RECIPIENT = "pin.secret@example.com";
    static final String ANGUS = "org.eclipse.angus.mail";
    static final String PROBE_LINE = "jakarta-mail-probe-line";

    @Test
    void mailLibraryDoesNotLogTrafficWhenItsParentIsAtTrace(CapturedOutput output) {
        withLogLevel("org.eclipse.angus", LogLevel.TRACE, null, this::sendOneMessage);

        assertThat(output.getAll()).doesNotContain(RECIPIENT);
    }

    // Positive control: with the library's own logger at TRACE (the pin removed) the same send prints the recipient.
    // PT: Controle positivo: com o logger da própria biblioteca em TRACE (sem a fixação), o mesmo envio imprime o destinatário.
    @Test
    void mailLibraryWouldLogTrafficWithoutThePin(CapturedOutput output) {
        withLogLevel(ANGUS, LogLevel.TRACE, LogLevel.INFO, this::sendOneMessage);

        assertThat(output.getAll()).contains(RECIPIENT);
    }

    // jakarta.mail is the API's own logger name: a plain java.util.logging record proves the pin, and the
    // control below proves the record would print without it.
    // PT: jakarta.mail é o nome do logger da própria API: um registro java.util.logging puro prova a fixação, e
    //     o controle abaixo prova que o registro seria impresso sem ela.
    @Test
    void jakartaMailLoggerIsPinnedWhenItsParentIsAtTrace(CapturedOutput output) {
        withLogLevel("jakarta", LogLevel.TRACE, null, this::logOnJakartaMail);

        assertThat(output.getAll()).doesNotContain(PROBE_LINE);
    }

    @Test
    void jakartaMailLoggerWouldPrintWithoutThePin(CapturedOutput output) {
        withLogLevel("jakarta.mail", LogLevel.TRACE, LogLevel.INFO, this::logOnJakartaMail);

        assertThat(output.getAll()).contains(PROBE_LINE);
    }

    private void logOnJakartaMail() {
        java.util.logging.Logger.getLogger("jakarta.mail").fine(PROBE_LINE);
    }

    private void sendOneMessage() {
        try (var smtp = new FakeSmtpServer()) {
            var sender = new JavaMailSenderImpl();
            sender.setHost("localhost");
            sender.setPort(smtp.port());
            var mime = sender.createMimeMessage();
            var helper = new org.springframework.mail.javamail.MimeMessageHelper(mime, "UTF-8");
            helper.setFrom("no-reply@snapledger.local");
            helper.setTo(RECIPIENT);
            helper.setSubject("probe");
            helper.setText("probe");
            sender.send(mime);
        } catch (Exception e) {
            throw new AssertionError("the probe email could not be sent", e);
        }
    }

    private static void withLogLevel(String name, LogLevel level, LogLevel restore, Runnable action) {
        var logging = LoggingSystem.get(MailLoggerPinIntegrationTest.class.getClassLoader());
        logging.setLogLevel(name, level);
        try {
            action.run();
        } finally {
            logging.setLogLevel(name, restore);
        }
    }
}
