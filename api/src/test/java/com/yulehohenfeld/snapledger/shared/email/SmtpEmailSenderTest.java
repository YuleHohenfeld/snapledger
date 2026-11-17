package com.yulehohenfeld.snapledger.shared.email;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import java.util.Properties;

import jakarta.mail.Message;
import jakarta.mail.Multipart;
import jakarta.mail.Session;
import jakarta.mail.internet.MimeMessage;

import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.mail.MailSendException;
import org.springframework.mail.javamail.JavaMailSender;

/**
 * The SMTP adapter builds one multipart text + HTML message from the configured address, and lets
 * a send failure reach the dispatcher.
 *
 * <p>PT: O adaptador SMTP monta uma mensagem multipart texto + HTML a partir do endereço
 * configurado, e deixa uma falha de envio chegar ao dispatcher.
 */
class SmtpEmailSenderTest {

    final JavaMailSender mailSender = mock(JavaMailSender.class);
    final SmtpEmailSender sender = new SmtpEmailSender(mailSender, new EmailProperties("no-reply@snapledger.local"));
    final Session session = Session.getInstance(new Properties());

    @Test
    void sendsOneMultipartMessageWithFromToSubjectAndBothParts() throws Exception {
        when(mailSender.createMimeMessage()).thenReturn(new MimeMessage(session));

        sender.send(new EmailMessage("ana@example.com", "Subject", "plain body", "<p>html body</p>"));

        var captor = ArgumentCaptor.forClass(MimeMessage.class);
        verify(mailSender).send(captor.capture());
        var sent = captor.getValue();
        sent.saveChanges();
        assertThat(sent.getFrom()[0].toString()).isEqualTo("no-reply@snapledger.local");
        assertThat(sent.getRecipients(Message.RecipientType.TO)[0].toString()).isEqualTo("ana@example.com");
        assertThat(sent.getSubject()).isEqualTo("Subject");
        var parts = flatten(sent.getContent());
        assertThat(parts).contains("plain body").contains("<p>html body</p>");
    }

    @Test
    void aMalformedRecipientFailsWithoutQuotingIt() {
        when(mailSender.createMimeMessage()).thenReturn(new MimeMessage(session));

        assertThatThrownBy(() -> sender.send(new EmailMessage("not an address@@", "S", "t", "<p>h</p>")))
                .isInstanceOf(org.springframework.mail.MailPreparationException.class)
                .satisfies(e -> {
                    assertThat(e.getMessage()).doesNotContain("not an address");
                    assertThat(e.getCause()).isNull();
                });
    }

    @Test
    void aSendFailureIsRethrownToTheCaller() {
        when(mailSender.createMimeMessage()).thenReturn(new MimeMessage(session));
        doThrow(new MailSendException("down")).when(mailSender).send(any(MimeMessage.class));

        assertThatThrownBy(() -> sender.send(new EmailMessage("ana@example.com", "S", "t", "<p>h</p>")))
                .isInstanceOf(MailSendException.class);
    }

    @Test
    void emailMessageToStringMasksTheRecipientAndOmitsBodies() {
        var text = new EmailMessage("ana@example.com", "Subject", "code 123456", "<p>code 123456</p>").toString();

        assertThat(text).doesNotContain("ana@example.com").doesNotContain("123456").contains("Subject");
    }

    private static String flatten(Object content) throws Exception {
        if (content instanceof Multipart multipart) {
            var out = new StringBuilder();
            for (int i = 0; i < multipart.getCount(); i++) {
                out.append(flatten(multipart.getBodyPart(i).getContent()));
            }
            return out.toString();
        }
        return String.valueOf(content);
    }
}
