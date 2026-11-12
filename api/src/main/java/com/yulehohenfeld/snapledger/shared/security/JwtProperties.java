package com.yulehohenfeld.snapledger.shared.security;

import java.time.Duration;
import java.util.Base64;

import javax.crypto.SecretKey;
import javax.crypto.spec.SecretKeySpec;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;

import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.validation.annotation.Validated;

/**
 * Access token settings (ADR 0004). Binding fails, and so the application does not start,
 * when the secret is missing, not Base64 or shorter than 256 bits. Error messages never
 * quote the secret, and {@link #toString()} masks it.
 *
 * <p>PT: Configurações do token de acesso (ADR 0004). A leitura falha, e com isso a aplicação não
 * sobe, quando o segredo está ausente, não é Base64 ou tem menos de 256 bits. As mensagens
 * de erro nunca citam o segredo, e o toString() o mascara.
 */
@Validated
@ConfigurationProperties("app.security.jwt")
public record JwtProperties(@NotBlank String secret,
                            @NotBlank String issuer,
                            @NotNull Duration accessTokenTtl) {

    /**
     * {@code aud} of every access token (ADR 0006). A constant, not a property: the contract
     * fixes the value, and making it configurable would only allow issuer and validator to
     * disagree. Other token types must use a different audience and a different key.
     *
     * <p>PT: O aud de todo token de acesso (ADR 0006). Uma constante, não uma propriedade: o
     * contrato fixa o valor, e torná-lo configurável só permitiria que quem emite e quem
     * valida discordassem. Outros tipos de token precisam usar outro audience e outra chave.
     */
    public static final String AUDIENCE = "snapledger-api";

    static final int MIN_SECRET_BYTES = 32;
    static final String INVALID_SECRET =
            "app.security.jwt.secret (JWT_SECRET) must be a single-line Base64 value of at least 256 bits";

    public JwtProperties {
        // Blank/null are reported by @NotBlank; here only a present value is checked.
        // PT: Vazio/nulo são reportados pelo @NotBlank; aqui só um valor presente é verificado.
        if (secret != null && !secret.isBlank() && decodedLength(secret) < MIN_SECRET_BYTES) {
            throw new IllegalArgumentException(INVALID_SECRET);
        }
        if (accessTokenTtl != null && (accessTokenTtl.isZero() || accessTokenTtl.isNegative())) {
            throw new IllegalArgumentException("app.security.jwt.access-token-ttl must be positive");
        }
    }

    /**
     * HMAC key for HS256 signing and verification.
     *
     * <p>PT: Chave HMAC para assinar e verificar com HS256.
     */
    public SecretKey key() {
        return new SecretKeySpec(Base64.getDecoder().decode(secret), "HmacSHA256");
    }

    @Override
    public String toString() {
        return "JwtProperties[issuer=" + issuer + ", accessTokenTtl=" + accessTokenTtl + ", secret=****]";
    }

    private static int decodedLength(String secret) {
        try {
            return Base64.getDecoder().decode(secret).length;
        } catch (IllegalArgumentException e) {
            // Not rethrown as a cause: the JDK message quotes the offending character of the secret.
            // PT: Não é relançada como causa: a mensagem do JDK cita o caractere inválido do
            //     segredo.
            return -1;
        }
    }
}
