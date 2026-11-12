package com.yulehohenfeld.snapledger.support;

import java.time.Duration;
import java.time.Instant;
import java.util.List;
import java.util.UUID;
import java.util.function.Consumer;

import javax.crypto.SecretKey;

import com.nimbusds.jose.jwk.source.ImmutableSecret;

import org.springframework.security.oauth2.jose.jws.MacAlgorithm;
import org.springframework.security.oauth2.jwt.JwsHeader;
import org.springframework.security.oauth2.jwt.JwtClaimsSet;
import org.springframework.security.oauth2.jwt.JwtEncoderParameters;
import org.springframework.security.oauth2.jwt.NimbusJwtEncoder;

import com.yulehohenfeld.snapledger.shared.security.JwtProperties;

/**
 * Signs access tokens for tests with the claims the application requires (ADR 0006), so every
 * test builds them the same way. Tests that need a broken token change exactly one claim through
 * the customizer.
 *
 * <p>PT: Assina tokens de acesso para testes com as claims que a aplicação exige (ADR 0006), para
 * que todo teste os monte do mesmo jeito. Testes que precisam de um token quebrado mudam
 * exatamente uma claim pelo customizer.
 */
public final class TestTokens {

    public static final Duration TTL = Duration.ofMinutes(15);

    private TestTokens() {
    }

    /**
     * A token that passes every validator at {@code now}, signed with the application key.
     *
     * <p>PT: Um token que passa em todos os validadores no instante {@code now}, assinado com a
     * chave da aplicação.
     */
    public static String valid(Instant now) {
        return sign(TestJwtSecret.key(), MacAlgorithm.HS256, now, claims -> { });
    }

    /**
     * Valid claims at {@code now}, then {@code customizer}, signed with {@code key} and {@code alg}.
     *
     * <p>PT: Claims válidas no instante {@code now}, depois o {@code customizer}, assinadas com
     * {@code key} e {@code alg}.
     */
    public static String sign(SecretKey key, MacAlgorithm alg, Instant now,
                              Consumer<JwtClaimsSet.Builder> customizer) {
        var claims = JwtClaimsSet.builder()
                .issuer(TestJwtSecret.ISSUER)
                .audience(List.of(JwtProperties.AUDIENCE))
                .subject(UUID.randomUUID().toString())
                .issuedAt(now)
                .expiresAt(now.plus(TTL));
        customizer.accept(claims);
        var encoder = new NimbusJwtEncoder(new ImmutableSecret<>(key));
        return encoder.encode(JwtEncoderParameters.from(JwsHeader.with(alg).build(), claims.build())).getTokenValue();
    }

    public static String bearer(String token) {
        return "Bearer " + token;
    }
}
