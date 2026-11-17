package com.yulehohenfeld.snapledger.shared.ratelimit;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import java.time.Duration;
import java.util.Set;

import jakarta.validation.Validation;

import org.junit.jupiter.api.Test;

/**
 * The limits are validated at startup and match the numbers of the contract's Limits table.
 *
 * <p>PT: Os limites são validados na subida e batem com os números da tabela Limits do contrato.
 */
class RateLimitPropertiesTest {

    @Test
    void theBucketsMapToTheirLimits() {
        var props = new RateLimitProperties(10, 20, 20, 5, 21, Duration.ofHours(1), 1000);

        assertThat(props.limitOf(RateLimitProperties.PASSWORD_RESET)).isEqualTo(10);
        assertThat(props.limitOf(RateLimitProperties.PASSWORD_RESET_CONFIRM)).isEqualTo(20);
        assertThat(props.limitOf(RateLimitProperties.PASSWORD_RESET_EMAIL)).isEqualTo(5);
        assertThat(props.limitOf(RateLimitProperties.PASSWORD_RESET_VERIFY_EMAIL)).isEqualTo(21);
    }

    @Test
    void aNonPositiveLimitFailsValidation() {
        try (var factory = Validation.buildDefaultValidatorFactory()) {
            var violations = factory.getValidator()
                    .validate(new RateLimitProperties(0, 20, 20, 5, 20, Duration.ofHours(1), 1000));

            assertThat(violations).hasSize(1);
        }
    }

    @Test
    void aNonPositiveWindowIsRefused() {
        assertThatThrownBy(() -> new RateLimitProperties(1, 1, 1, 1, 1, Duration.ZERO, 1))
                .isInstanceOf(IllegalArgumentException.class);
        assertThatThrownBy(() -> new RateLimitProperties(1, 1, 1, 1, 1, Duration.ofSeconds(-1), 1))
                .isInstanceOf(IllegalArgumentException.class);
    }

    @Test
    void emailKeysAreCaseInsensitiveHexDigestsThatNeverContainTheAddress() {
        var key = RateLimitKeys.ofEmail("Ana@Example.com");

        assertThat(key).isEqualTo(RateLimitKeys.ofEmail("ana@example.com")).matches("^[0-9a-f]{64}$");
        assertThat(key).doesNotContain("ana").doesNotContain("example");
        assertThat(Set.of(key, RateLimitKeys.ofEmail("bob@example.com"))).hasSize(2);
    }
}
