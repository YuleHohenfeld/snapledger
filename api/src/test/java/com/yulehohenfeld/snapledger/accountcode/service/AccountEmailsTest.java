package com.yulehohenfeld.snapledger.accountcode.service;

import static org.assertj.core.api.Assertions.assertThat;

import java.time.Duration;

import org.junit.jupiter.api.Test;

import com.yulehohenfeld.snapledger.accountcode.config.AccountCodeProperties;
import com.yulehohenfeld.snapledger.support.TestJwtSecret;

/**
 * The messages carry the code and the expiry in both parts, and no link, image or tracking.
 *
 * <p>PT: As mensagens levam o código e a validade nas duas partes, e nenhum link, imagem ou rastreamento.
 */
class AccountEmailsTest {

    final AccountEmails emails = new AccountEmails(
            new AccountCodeProperties(TestJwtSecret.generate(), Duration.ofMinutes(15), 5, Duration.ofSeconds(60), 5, 10, Duration.ofHours(24)));

    @Test
    void codeMessagesCarryTheCodeAndTheExpiryInTextAndHtml() {
        for (var message : new com.yulehohenfeld.snapledger.shared.email.EmailMessage[] {
                emails.verificationCode("ana@example.com", "012345"),
                emails.passwordResetCode("ana@example.com", "012345")}) {
            assertThat(message.to()).isEqualTo("ana@example.com");
            assertThat(message.subject()).doesNotContain("012345");
            assertThat(message.text()).contains("012345").contains("15 minutes");
            assertThat(message.html()).contains("012345").contains("15 minutes")
                    .doesNotContain("http").doesNotContain("<img").doesNotContain("<a ");
        }
    }

    @Test
    void passwordChangedMessageHasNoCodeAndNoLink() {
        var message = emails.passwordChanged("ana@example.com");

        assertThat(message.text()).contains("password").doesNotContainPattern("\\d{6}").doesNotContain("http");
        assertThat(message.html()).doesNotContain("http").doesNotContain("<img").doesNotContain("<a ");
    }
}
