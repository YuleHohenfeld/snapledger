package com.yulehohenfeld.snapledger.accountcode.config;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.Test;
import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.boot.test.context.runner.ApplicationContextRunner;
import org.springframework.context.annotation.Configuration;
import org.springframework.context.annotation.Import;

import com.yulehohenfeld.snapledger.shared.security.JwtProperties;
import com.yulehohenfeld.snapledger.support.TestJwtSecret;

/**
 * The application refuses to start when both secrets are the same key, and the error quotes neither.
 *
 * <p>PT: A aplicação se recusa a subir quando os dois segredos são a mesma chave, e o erro não cita nenhum.
 */
class DistinctSecretsValidatorTest {

    private final ApplicationContextRunner runner = new ApplicationContextRunner()
            .withUserConfiguration(Config.class)
            .withPropertyValues(
                    "app.security.jwt.issuer=snapledger-api",
                    "app.security.jwt.access-token-ttl=15m",
                    "app.account-code.ttl=15m",
                    "app.account-code.max-attempts=5",
                    "app.account-code.resend-cooldown=60s",
                    "app.account-code.max-sends-per-hour=5",
                    "app.account-code.max-failures-per-day=10",
                    "app.account-code.failure-window=24h");

    @Test
    void startsWithDifferentSecrets() {
        runner.withPropertyValues("app.security.jwt.secret=" + TestJwtSecret.generate(),
                "app.account-code.secret=" + TestJwtSecret.generate())
                .run(context -> assertThat(context).hasNotFailed());
    }

    @Test
    void failsWithTheSameSecretAndNeverQuotesIt() {
        var secret = TestJwtSecret.generate();

        runner.withPropertyValues("app.security.jwt.secret=" + secret, "app.account-code.secret=" + secret)
                .run(context -> {
                    assertThat(context).hasFailed();
                    var failure = context.getStartupFailure();
                    var messages = new StringBuilder();
                    for (Throwable t = failure; t != null; t = t.getCause()) {
                        messages.append(t.getMessage()).append('\n');
                    }
                    assertThat(messages.toString()).contains("must differ").doesNotContain(secret);
                });
    }

    @Configuration(proxyBeanMethods = false)
    @EnableConfigurationProperties({AccountCodeProperties.class, JwtProperties.class})
    @Import(DistinctSecretsValidator.class)
    static class Config {
    }
}
