package com.yulehohenfeld.snapledger.accountcode.service;

import static org.assertj.core.api.Assertions.assertThat;

import java.time.Duration;
import java.util.UUID;

import org.junit.jupiter.api.Test;

import com.yulehohenfeld.snapledger.accountcode.config.AccountCodeProperties;
import com.yulehohenfeld.snapledger.accountcode.entity.CodePurpose;
import com.yulehohenfeld.snapledger.support.TestJwtSecret;

/**
 * The hash is a keyed, purpose- and user-bound HMAC in lowercase hex, compared in constant time.
 *
 * <p>PT: O hash é um HMAC com chave, ligado à finalidade e ao usuário, em hex minúsculo, comparado
 * em tempo constante.
 */
class AccountCodeHasherTest {

    final UUID userId = UUID.randomUUID();
    final AccountCodeHasher hasher = hasherWith(TestJwtSecret.generate());

    @Test
    void hashIs64LowercaseHexCharactersAndStable() {
        var hash = hasher.hash(CodePurpose.PASSWORD_RESET, userId, "012345");

        assertThat(hash).matches("^[0-9a-f]{64}$").isEqualTo(hasher.hash(CodePurpose.PASSWORD_RESET, userId, "012345"));
    }

    @Test
    void hashChangesWithPurposeUserCodeAndSecret() {
        var base = hasher.hash(CodePurpose.PASSWORD_RESET, userId, "012345");

        assertThat(hasher.hash(CodePurpose.EMAIL_VERIFICATION, userId, "012345")).isNotEqualTo(base);
        assertThat(hasher.hash(CodePurpose.PASSWORD_RESET, UUID.randomUUID(), "012345")).isNotEqualTo(base);
        assertThat(hasher.hash(CodePurpose.PASSWORD_RESET, userId, "012346")).isNotEqualTo(base);
        assertThat(hasherWith(TestJwtSecret.generate()).hash(CodePurpose.PASSWORD_RESET, userId, "012345"))
                .isNotEqualTo(base);
    }

    @Test
    void matchesOnlyTheSameCodePurposeAndUser() {
        var stored = hasher.hash(CodePurpose.EMAIL_VERIFICATION, userId, "123456");

        assertThat(hasher.matches(CodePurpose.EMAIL_VERIFICATION, userId, "123456", stored)).isTrue();
        assertThat(hasher.matches(CodePurpose.EMAIL_VERIFICATION, userId, "123457", stored)).isFalse();
        assertThat(hasher.matches(CodePurpose.PASSWORD_RESET, userId, "123456", stored)).isFalse();
        assertThat(hasher.matches(CodePurpose.EMAIL_VERIFICATION, UUID.randomUUID(), "123456", stored)).isFalse();
    }

    static AccountCodeHasher hasherWith(String secret) {
        return new AccountCodeHasher(new AccountCodeProperties(secret, Duration.ofMinutes(15), 5,
                Duration.ofSeconds(60), 5, 10, Duration.ofHours(24)));
    }
}
