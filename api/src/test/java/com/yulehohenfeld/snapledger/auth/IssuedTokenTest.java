package com.yulehohenfeld.snapledger.auth;

import static org.assertj.core.api.Assertions.assertThat;

import java.time.Duration;
import java.util.UUID;

import org.junit.jupiter.api.Test;

/**
 * IssuedToken carries a live credential: its toString must never show the value.
 *
 * <p>PT: O IssuedToken carrega uma credencial viva: o toString dele nunca pode mostrar o valor.
 */
class IssuedTokenTest {

    @Test
    void toStringMasksTheValueAndKeepsTheTtl() {
        var value = "token-" + UUID.randomUUID();

        var issued = new IssuedToken(value, Duration.ofMinutes(15));

        assertThat(issued.toString())
                .isEqualTo("IssuedToken[value=****, ttl=PT15M]")
                .doesNotContain(value);
    }
}
