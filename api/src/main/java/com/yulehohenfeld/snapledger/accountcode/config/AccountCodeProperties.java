package com.yulehohenfeld.snapledger.accountcode.config;

import java.time.Duration;
import java.util.Base64;

import javax.crypto.SecretKey;
import javax.crypto.spec.SecretKeySpec;

import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;

import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.validation.annotation.Validated;

/**
 * Account code settings (ADR 0012). Binding fails, and so the application does not start, when the
 * secret is missing, not Base64 or shorter than 256 bits, or a limit is not positive. Messages never
 * quote the secret, and {@link #toString()} masks it.
 *
 * <p>PT: Configurações dos códigos de conta (ADR 0012). A leitura falha, e com isso a aplicação não
 * sobe, quando o segredo está ausente, não é Base64 ou tem menos de 256 bits, ou um limite não é
 * positivo. As mensagens nunca citam o segredo, e o toString() o mascara.
 * Notes: docs/code-notes/account-code.md#accountcodeproperties
 */
@Validated
@ConfigurationProperties("app.account-code")
public record AccountCodeProperties(@NotBlank String secret,
                                    @NotNull Duration ttl,
                                    @Min(1) int maxAttempts,
                                    @NotNull Duration resendCooldown,
                                    @Min(1) int maxSendsPerHour,
                                    @Min(1) int maxFailuresPerDay,
                                    @NotNull Duration failureWindow) {

    static final int MIN_SECRET_BYTES = 32;
    static final String INVALID_SECRET =
            "app.account-code.secret (ACCOUNT_CODE_SECRET) must be a single-line Base64 value of at least 256 bits";

    public AccountCodeProperties {
        // Blank/null are reported by @NotBlank; here only a present value is checked.
        // PT: Vazio/nulo são reportados pelo @NotBlank; aqui só um valor presente é verificado.
        if (secret != null && !secret.isBlank() && decodedLength(secret) < MIN_SECRET_BYTES) {
            throw new IllegalArgumentException(INVALID_SECRET);
        }
        if (ttl != null && (ttl.isZero() || ttl.isNegative())) {
            throw new IllegalArgumentException("app.account-code.ttl must be positive");
        }
        if (resendCooldown != null && resendCooldown.isNegative()) {
            throw new IllegalArgumentException("app.account-code.resend-cooldown must not be negative");
        }
        if (failureWindow != null && (failureWindow.isZero() || failureWindow.isNegative())) {
            throw new IllegalArgumentException("app.account-code.failure-window must be positive");
        }
    }

    /** HMAC key that hashes the codes. PT: Chave HMAC que gera o hash dos códigos. */
    public SecretKey key() {
        return new SecretKeySpec(Base64.getDecoder().decode(secret), "HmacSHA256");
    }

    @Override
    public String toString() {
        return "AccountCodeProperties[ttl=" + ttl + ", maxAttempts=" + maxAttempts + ", resendCooldown="
                + resendCooldown + ", maxSendsPerHour=" + maxSendsPerHour + ", maxFailuresPerDay=" + maxFailuresPerDay
                + ", failureWindow=" + failureWindow + ", secret=****]";
    }

    private static int decodedLength(String secret) {
        try {
            return Base64.getDecoder().decode(secret).length;
        } catch (IllegalArgumentException e) {
            // Not rethrown as a cause: the JDK message quotes the offending character of the secret.
            // PT: Não é relançada como causa: a mensagem do JDK cita o caractere inválido do segredo.
            return -1;
        }
    }
}
