package com.yulehohenfeld.snapledger.shared.security;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import java.io.PrintWriter;
import java.io.StringWriter;
import java.security.SecureRandom;
import java.time.Duration;
import java.util.Base64;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.springframework.boot.WebApplicationType;
import org.springframework.boot.builder.SpringApplicationBuilder;
import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.boot.test.context.runner.ApplicationContextRunner;
import org.springframework.boot.test.system.CapturedOutput;
import org.springframework.boot.test.system.OutputCaptureExtension;
import org.springframework.context.annotation.Configuration;

import com.yulehohenfeld.snapledger.support.TestJwtSecret;

/** Fail-fast binding of app.security.jwt, independent of the machine (.env is never loaded). */
@ExtendWith(OutputCaptureExtension.class)
class JwtPropertiesTest {

    private final ApplicationContextRunner runner = new ApplicationContextRunner()
            .withUserConfiguration(JwtPropertiesConfig.class)
            .withPropertyValues(
                    "app.security.jwt.issuer=snapledger-api",
                    "app.security.jwt.access-token-ttl=15m");

    @Test
    void bindsValidSecretAndExposesHmacKey() {
        var secret = TestJwtSecret.generate();
        runner.withPropertyValues("app.security.jwt.secret=" + secret).run(context -> {
            assertThat(context).hasNotFailed();
            var props = context.getBean(JwtProperties.class);
            assertThat(props.key().getAlgorithm()).isEqualTo("HmacSHA256");
            assertThat(props.key().getEncoded()).hasSize(64);
            assertThat(props.accessTokenTtl()).isEqualTo(Duration.ofMinutes(15));
        });
    }

    @Test
    void failsWhenSecretIsMissing() {
        runner.run(context -> assertThat(context).hasFailed());
    }

    @Test
    void failsWhenSecretIsBlank() {
        runner.withPropertyValues("app.security.jwt.secret=   ")
                .run(context -> assertThat(context).hasFailed());
    }

    @Test
    void failsWhenSecretIsShorterThan256BitsWithoutRevealingIt() {
        var shortSecret = randomBase64(31);
        runner.withPropertyValues("app.security.jwt.secret=" + shortSecret).run(context -> {
            assertThat(context).hasFailed();
            assertThat(fullTrace(context.getStartupFailure()))
                    .contains("at least 256 bits")
                    .doesNotContain(shortSecret);
        });
    }

    @Test
    void failsWhenSecretIsNotBase64WithoutRevealingIt() {
        var notBase64 = randomBase64(48).replace('A', '-').replace('B', '!') + "-!";
        runner.withPropertyValues("app.security.jwt.secret=" + notBase64).run(context -> {
            assertThat(context).hasFailed();
            var trace = fullTrace(context.getStartupFailure());
            assertThat(trace).contains("Base64").doesNotContain(notBase64);
            // The JDK decoder message would quote the offending character; it must not leak.
            assertThat(trace).doesNotContain("Illegal base64 character");
        });
    }

    @Test
    void failsWhenAccessTokenTtlIsNotPositive() {
        runner.withPropertyValues(
                        "app.security.jwt.secret=" + TestJwtSecret.generate(),
                        "app.security.jwt.access-token-ttl=0s")
                .run(context -> assertThat(context).hasFailed());
    }

    @Test
    void startupFailureOutputNeverContainsTheSecret(CapturedOutput output) {
        var shortSecret = randomBase64(16);
        var app = new SpringApplicationBuilder(JwtPropertiesConfig.class)
                .web(WebApplicationType.NONE)
                .properties(
                        "spring.config.name=jwt-properties-test-no-config-file", // never loads application.properties/.env
                        "spring.main.banner-mode=off",
                        "app.security.jwt.issuer=snapledger-api",
                        "app.security.jwt.access-token-ttl=15m",
                        "app.security.jwt.secret=" + shortSecret);

        assertThatThrownBy(app::run).satisfies(ex -> assertThat(fullTrace(ex)).doesNotContain(shortSecret));
        assertThat(output.getAll())
                .contains("at least 256 bits")
                .doesNotContain(shortSecret);
    }

    @Test
    void toStringMasksTheSecret() {
        var secret = TestJwtSecret.generate();
        var props = new JwtProperties(secret, "snapledger-api", Duration.ofMinutes(15));

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
    @EnableConfigurationProperties(JwtProperties.class)
    static class JwtPropertiesConfig {
    }
}
