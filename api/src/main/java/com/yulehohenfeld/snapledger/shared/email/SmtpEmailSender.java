package com.yulehohenfeld.snapledger.shared.email;

import jakarta.mail.MessagingException;

import org.springframework.mail.MailPreparationException;
import org.springframework.mail.javamail.JavaMailSender;
import org.springframework.mail.javamail.MimeMessageHelper;
import org.springframework.stereotype.Component;

/**
 * SMTP adapter of {@link EmailSender}: a multipart text + HTML message, no tracking, no links to
 * outside, no external images.
 *
 * <p>PT: Adaptador SMTP do {@link EmailSender}: mensagem multipart texto + HTML, sem rastreamento,
 * sem links externos, sem imagens externas.
 * Notes: docs/code-notes/email.md#smtpemailsender
 */
@Component
public class SmtpEmailSender implements EmailSender {

    private final JavaMailSender mailSender;
    private final EmailProperties properties;

    public SmtpEmailSender(JavaMailSender mailSender, EmailProperties properties) {
        this.mailSender = mailSender;
        this.properties = properties;
    }

    @Override
    public void send(EmailMessage message) {
        var mime = mailSender.createMimeMessage();
        try {
            var helper = new MimeMessageHelper(mime, true, "UTF-8");
            helper.setFrom(properties.from());
            helper.setTo(message.to());
            helper.setSubject(message.subject());
            helper.setText(message.text(), message.html());
        } catch (MessagingException e) {
            // The cause is dropped on purpose: an AddressException message quotes the recipient.
            // PT: A causa é descartada de propósito: a mensagem de AddressException cita o destinatário.
            throw new MailPreparationException("Could not build the email");
        }
        mailSender.send(mime);
    }
}
