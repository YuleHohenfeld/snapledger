package com.yulehohenfeld.snapledger.auth;

import static org.assertj.core.api.Assertions.assertThat;

import java.time.Duration;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.boot.test.context.runner.ApplicationContextRunner;
import org.springframework.context.annotation.Configuration;

/**
 * Fail-fast binding of app.security.refresh-token, independent of the machine (.env is never
 * loaded).
 *
 * <p>PT: Leitura com falha rápida de app.security.refresh-token, independente da máquina (o .env
 * nunca é carregado).
 */
class RefreshTokenPropertiesTest {

    private final ApplicationContextRunner runner = new ApplicationContextRunner()
            .withUserConfiguration(RefreshTokenPropertiesConfig.class);

    @Test
    void bindsTheTtl() {
        runner.withPropertyValues("app.security.refresh-token.ttl=30d").run(context -> {
            assertThat(context).hasNotFailed();
            assertThat(context.getBean(RefreshTokenProperties.class).ttl()).isEqualTo(Duration.ofDays(30));
        });
    }

    @Test
    void failsWhenTheTtlIsMissing() {
        runner.run(context -> assertThat(context).hasFailed());
    }

    @ParameterizedTest
    @ValueSource(strings = {"0s", "-1d"})
    void failsWhenTheTtlIsNotPositive(String ttl) {
        runner.withPropertyValues("app.security.refresh-token.ttl=" + ttl)
                .run(context -> assertThat(context).hasFailed());
    }

    @Configuration(proxyBeanMethods = false)
    @EnableConfigurationProperties(RefreshTokenProperties.class)
    static class RefreshTokenPropertiesConfig {
    }
}
