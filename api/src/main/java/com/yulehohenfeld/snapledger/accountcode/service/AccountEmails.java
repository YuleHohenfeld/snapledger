package com.yulehohenfeld.snapledger.accountcode.service;

import org.springframework.stereotype.Component;

import com.yulehohenfeld.snapledger.accountcode.config.AccountCodeProperties;
import com.yulehohenfeld.snapledger.shared.email.EmailMessage;

/**
 * The three account emails, in English: plain text plus a simple HTML copy with no links, images or tracking.
 *
 * <p>PT: Os três emails da conta, em inglês: texto puro mais uma cópia HTML simples, sem links, imagens ou rastreamento.
 * Notes: docs/code-notes/account-code.md#accountemails
 */
@Component
public class AccountEmails {

    private final long ttlMinutes;

    public AccountEmails(AccountCodeProperties properties) {
        this.ttlMinutes = properties.ttl().toMinutes();
    }

    public EmailMessage verificationCode(String to, String code) {
        return codeMessage(to, "Your SnapLedger verification code",
                "Use this code to verify your email address.", code);
    }

    public EmailMessage passwordResetCode(String to, String code) {
        return codeMessage(to, "Your SnapLedger password reset code",
                "Use this code to reset your password. If you did not ask for it, ignore this email.", code);
    }

    public EmailMessage passwordChanged(String to) {
        var line1 = "The password of your SnapLedger account was just changed.";
        var line2 = "If this was not you, reset your password again and review your account.";
        return new EmailMessage(to, "Your SnapLedger password was changed",
                line1 + "\n\n" + line2 + "\n",
                "<p>" + line1 + "</p><p>" + line2 + "</p>");
    }

    private EmailMessage codeMessage(String to, String subject, String intro, String code) {
        var expiry = "The code expires in " + ttlMinutes + " minutes and works once.";
        var never = "SnapLedger will never ask you for this code by any other channel.";
        return new EmailMessage(to, subject,
                intro + "\n\nCode: " + code + "\n\n" + expiry + "\n" + never + "\n",
                "<p>" + intro + "</p><p style=\"font-size:24px;letter-spacing:4px\"><strong>" + code
                        + "</strong></p><p>" + expiry + " " + never + "</p>");
    }
}
