package com.yulehohenfeld.snapledger.accountcode.config;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import java.io.PrintWriter;
import java.io.StringWriter;
import java.security.SecureRandom;
import java.time.Duration;
import java.util.Base64;

import org.junit.jupiter.api.Test;
import org.springframework.boot.WebApplicationType;
import org.springframework.boot.builder.SpringApplicationBuilder;
import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.boot.test.context.runner.ApplicationContextRunner;
import org.springframework.context.annotation.Configuration;

import com.yulehohenfeld.snapledger.support.TestJwtSecret;

/**
 * Fail-fast binding of app.account-code, independent of the machine (.env is never loaded).
 *
 * <p>PT: Leitura com falha rápida de app.account-code, independente da máquina (o .env nunca é
 * carregado).
 */
class AccountCodePropertiesTest {

    private final ApplicationContextRunner runner = new ApplicationContextRunner()
            .withUserConfiguration(PropertiesConfig.class)
            .withPropertyValues(
                    "app.account-code.ttl=15m",
                    "app.account-code.max-attempts=5",
                    "app.account-code.resend-cooldown=60s",
                    "app.account-code.max-sends-per-hour=5",
                    "app.account-code.max-failures-per-day=10",
                    "app.account-code.failure-window=24h");

    @Test
    void bindsAValidConfigurationAndExposesTheHmacKey() {
        runner.withPropertyValues("app.account-code.secret=" + TestJwtSecret.generate()).run(context -> {
            assertThat(context).hasNotFailed();
            var props = context.getBean(AccountCodeProperties.class);
            assertThat(props.key().getAlgorithm()).isEqualTo("HmacSHA256");
            assertThat(props.ttl()).isEqualTo(Duration.ofMinutes(15));
            assertThat(props.maxAttempts()).isEqualTo(5);
            assertThat(props.resendCooldown()).isEqualTo(Duration.ofSeconds(60));
            assertThat(props.maxSendsPerHour()).isEqualTo(5);
            assertThat(props.maxFailuresPerDay()).isEqualTo(10);
            assertThat(props.failureWindow()).isEqualTo(Duration.ofHours(24));
        });
    }

    @Test
    void failsWhenTheSecretIsMissingOrBlank() {
        runner.run(context -> assertThat(context).hasFailed());
        runner.withPropertyValues("app.account-code.secret=   ").run(context -> assertThat(context).hasFailed());
    }

    @Test
    void failsWhenTheSecretIsShorterThan256Bits() {
        runner.withPropertyValues("app.account-code.secret=" + randomBase64(31))
                .run(context -> assertThat(context).hasFailed());
    }

    @Test
    void failsWhenTheSecretIsNotBase64() {
        runner.withPropertyValues("app.account-code.secret=not base64 !!! not base64 !!! not base64 !!!")
                .run(context -> assertThat(context).hasFailed());
    }

    @Test
    void failsWhenALimitIsNotPositive() {
        var secret = "app.account-code.secret=" + TestJwtSecret.generate();
        runner.withPropertyValues(secret, "app.account-code.ttl=0s").run(context -> assertThat(context).hasFailed());
        runner.withPropertyValues(secret, "app.account-code.max-attempts=0")
                .run(context -> assertThat(context).hasFailed());
        runner.withPropertyValues(secret, "app.account-code.max-sends-per-hour=0")
                .run(context -> assertThat(context).hasFailed());
        runner.withPropertyValues(secret, "app.account-code.max-failures-per-day=0")
                .run(context -> assertThat(context).hasFailed());
        runner.withPropertyValues(secret, "app.account-code.failure-window=0s")
                .run(context -> assertThat(context).hasFailed());
    }

    @Test
    void startupFailureOutputNeverContainsTheSecret() {
        var shortSecret = randomBase64(16);
        var app = new SpringApplicationBuilder(PropertiesConfig.class)
                .web(WebApplicationType.NONE)
                .properties(
                        "spring.config.name=account-code-properties-test-no-config-file", // never loads application.properties/.env
                        // PT: nunca carrega o application.properties/.env
                        "spring.main.banner-mode=off",
                        "app.account-code.ttl=15m",
                        "app.account-code.max-attempts=5",
                        "app.account-code.resend-cooldown=60s",
                        "app.account-code.max-sends-per-hour=5",
                        "app.account-code.max-failures-per-day=10",
                        "app.account-code.failure-window=24h",
                        "app.account-code.secret=" + shortSecret);

        assertThatThrownBy(app::run).satisfies(ex -> assertThat(fullTrace(ex))
                .contains("at least 256 bits")
                .doesNotContain(shortSecret));
    }

    @Test
    void toStringMasksTheSecret() {
        var secret = TestJwtSecret.generate();
        var props = new AccountCodeProperties(secret, Duration.ofMinutes(15), 5, Duration.ofSeconds(60), 5, 10, Duration.ofHours(24));

        assertThat(props.toString()).doesNotContain(secret).contains("secret=****");
    }

    private static String randomBase64(int bytes) {
        var raw = new byte[bytes];
        new SecureRandom().nextBytes(raw);
        return Base64.getEncoder().encodeToString(raw);
    }

    private static String fullTrace(Throwable failure) {
        var writer = new StringWriter();
        failure.printStackTrace(new PrintWriter(writer));
        return writer.toString();
    }

    @Configuration(proxyBeanMethods = false)
    @EnableConfigurationProperties(AccountCodeProperties.class)
    static class PropertiesConfig {
    }
}
