package com.yulehohenfeld.snapledger.shared.ratelimit;

import java.time.Duration;

import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotNull;

import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.validation.annotation.Validated;

/**
 * Limits per window (default one hour) of the code endpoints; binding fails, so the application
 * does not start, when a limit is not positive.
 *
 * <p>PT: Limites por janela (padrão uma hora) dos endpoints de código; a leitura falha, e com isso
 * a aplicação não sobe, quando um limite não é positivo.
 * Notes: docs/code-notes/security.md#rate-limiting
 */
@Validated
@ConfigurationProperties("app.rate-limit")
public record RateLimitProperties(@Min(1) int passwordResetPerIp,
                                  @Min(1) int passwordResetVerifyPerIp,
                                  @Min(1) int passwordResetConfirmPerIp,
                                  @Min(1) int passwordResetPerEmail,
                                  @Min(1) int passwordResetVerifyPerEmail,
                                  @NotNull Duration window,
                                  @Min(1) int maxTrackedKeys) {

    public static final String PASSWORD_RESET = "password-reset";
    public static final String PASSWORD_RESET_VERIFY = "password-reset-verify";
    public static final String PASSWORD_RESET_CONFIRM = "password-reset-confirm";
    public static final String PASSWORD_RESET_EMAIL = "password-reset-email";
    public static final String PASSWORD_RESET_VERIFY_EMAIL = "password-reset-verify-email";

    public RateLimitProperties {
        if (window != null && (window.isZero() || window.isNegative())) {
            throw new IllegalArgumentException("app.rate-limit.window must be positive");
        }
    }

    /** The limit of a bucket; an unknown name is a programming error. PT: O limite de um bucket; nome desconhecido é erro de programação. */
    public int limitOf(String bucket) {
        return switch (bucket) {
            case PASSWORD_RESET -> passwordResetPerIp;
            case PASSWORD_RESET_VERIFY -> passwordResetVerifyPerIp;
            case PASSWORD_RESET_CONFIRM -> passwordResetConfirmPerIp;
            case PASSWORD_RESET_EMAIL -> passwordResetPerEmail;
            case PASSWORD_RESET_VERIFY_EMAIL -> passwordResetVerifyPerEmail;
            default -> throw new IllegalArgumentException("Unknown rate limit bucket: " + bucket);
        };
    }
}
