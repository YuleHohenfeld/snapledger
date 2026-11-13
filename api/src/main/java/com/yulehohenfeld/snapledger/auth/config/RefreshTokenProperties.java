package com.yulehohenfeld.snapledger.auth.config;

import java.time.Duration;

import jakarta.validation.constraints.NotNull;

import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.validation.annotation.Validated;

/** Refresh token TTL; a missing or non-positive value stops startup. PT: TTL ausente ou não positivo impede a subida.
 *  Notes: docs/code-notes/auth.md#refreshtokenproperties */
@Validated
@ConfigurationProperties("app.security.refresh-token")
public record RefreshTokenProperties(@NotNull Duration ttl) {

    public RefreshTokenProperties {
        // Null is reported by @NotNull; here only a present value is checked.
        // PT: Nulo é reportado pelo @NotNull; aqui só um valor presente é verificado.
        if (ttl != null && (ttl.isZero() || ttl.isNegative())) {
            throw new IllegalArgumentException("app.security.refresh-token.ttl must be positive");
        }
    }
}
