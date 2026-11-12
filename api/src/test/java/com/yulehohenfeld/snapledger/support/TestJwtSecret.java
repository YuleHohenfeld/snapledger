package com.yulehohenfeld.snapledger.support;

import java.security.SecureRandom;
import java.util.Base64;

import javax.crypto.SecretKey;
import javax.crypto.spec.SecretKeySpec;

import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.context.annotation.Bean;
import org.springframework.test.context.DynamicPropertyRegistrar;

/**
 * Supplies a random JWT signing secret, generated once per test JVM, so no test contains a
 * literal secret and none depends on the developer's .env. Import it in any test whose
 * context binds JwtProperties. One value per JVM keeps Spring's context cache effective.
 *
 * <p>PT: Fornece um segredo aleatório de assinatura de JWT, gerado uma vez por JVM de teste, para
 * que nenhum teste contenha um segredo literal e nenhum dependa do .env do desenvolvedor. Importe
 * em todo teste cujo contexto lê o JwtProperties. Um valor por JVM mantém o cache de contextos do
 * Spring eficaz.
 */
@TestConfiguration(proxyBeanMethods = false)
public class TestJwtSecret {

    public static final String ISSUER = "snapledger-api";

    private static final String SECRET = generate();

    @Bean
    DynamicPropertyRegistrar jwtSecretRegistrar() {
        return registry -> registry.add("app.security.jwt.secret", () -> SECRET);
    }

    /**
     * The Base64 secret the application context is using.
     *
     * <p>PT: O segredo em Base64 que o contexto da aplicação está usando.
     */
    public static String value() {
        return SECRET;
    }

    /**
     * Same key as the application, for signing tokens inside tests.
     *
     * <p>PT: A mesma chave da aplicação, para assinar tokens dentro dos testes.
     */
    public static SecretKey key() {
        return new SecretKeySpec(Base64.getDecoder().decode(SECRET), "HmacSHA256");
    }

    /**
     * A fresh random 64-byte secret, Base64-encoded.
     *
     * <p>PT: Um segredo aleatório novo de 64 bytes, codificado em Base64.
     */
    public static String generate() {
        var bytes = new byte[64];
        new SecureRandom().nextBytes(bytes);
        return Base64.getEncoder().encodeToString(bytes);
    }
}
