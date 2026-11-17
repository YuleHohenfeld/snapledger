package com.yulehohenfeld.snapledger.support;

import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.context.annotation.Bean;
import org.springframework.test.context.DynamicPropertyRegistrar;

/**
 * Supplies a random account code secret, generated once per test JVM, so no test contains a literal
 * secret and none depends on the developer's .env. {@link TestJwtSecret} imports it, so every context
 * that binds the JWT secret also binds this one.
 *
 * <p>PT: Fornece um segredo aleatório dos códigos de conta, gerado uma vez por JVM de teste, para
 * que nenhum teste contenha um segredo literal e nenhum dependa do .env do desenvolvedor. O
 * {@link TestJwtSecret} o importa, então todo contexto que lê o segredo do JWT lê este também.
 */
@TestConfiguration(proxyBeanMethods = false)
public class TestAccountCodeSecret {

    private static final String SECRET = TestJwtSecret.generate();

    @Bean
    DynamicPropertyRegistrar accountCodeSecretRegistrar() {
        return registry -> registry.add("app.account-code.secret", () -> SECRET);
    }

    public static String value() {
        return SECRET;
    }
}
