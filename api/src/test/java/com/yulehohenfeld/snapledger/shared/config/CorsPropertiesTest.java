package com.yulehohenfeld.snapledger.shared.config;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.boot.test.context.runner.ApplicationContextRunner;
import org.springframework.context.annotation.Configuration;

class CorsPropertiesTest {

    private final ApplicationContextRunner runner = new ApplicationContextRunner()
            .withUserConfiguration(CorsPropertiesConfig.class);

    @Test
    void parsesCommaSeparatedOriginsAndTrimsThem() {
        runner.withPropertyValues("app.cors.allowed-origins= http://localhost:8081 ,https://app.example.com ,")
                .run(context -> assertThat(context.getBean(CorsProperties.class).allowedOrigins())
                        .containsExactly("http://localhost:8081", "https://app.example.com"));
    }

    @Test
    void blankValueAllowsNoOrigin() {
        runner.withPropertyValues("app.cors.allowed-origins=")
                .run(context -> assertThat(context.getBean(CorsProperties.class).allowedOrigins()).isEmpty());
    }

    @Test
    void missingPropertyAllowsNoOrigin() {
        runner.run(context -> assertThat(context.getBean(CorsProperties.class).allowedOrigins()).isEmpty());
    }

    @Test
    void wildcardOriginFailsStartup() {
        runner.withPropertyValues("app.cors.allowed-origins=http://localhost:8081,*")
                .run(context -> assertThat(context).hasFailed());
    }

    @Test
    void wildcardInsideAnOriginFailsStartup() {
        runner.withPropertyValues("app.cors.allowed-origins=https://*.example.com")
                .run(context -> assertThat(context).hasFailed());
    }

    @ParameterizedTest
    @ValueSource(strings = {
            "http://localhost:8081",
            "https://app.example.com",
            "https://app.example.com:8443",
            "http://127.0.0.1:3000"})
    void exactOriginIsAccepted(String origin) {
        runner.withPropertyValues("app.cors.allowed-origins=" + origin)
                .run(context -> assertThat(context.getBean(CorsProperties.class).allowedOrigins())
                        .containsExactly(origin));
    }

    @ParameterizedTest
    @ValueSource(strings = {
            "*",
            "https://*.example.com",
            "null",
            "NULL",
            "app.example.com",                // no scheme
                                              // PT: sem esquema
            "localhost:8081",                 // parsed as scheme "localhost"
                                              // PT: lido como esquema "localhost"
            "ftp://app.example.com",
            "file:///etc/passwd",
            "http://",                        // no host
                                              // PT: sem host
            "https://exa mple.com",           // not a URI
                                              // PT: não é uma URI
            "http://localhost:8081/",         // trailing slash never matches a browser Origin
                                              // PT: a barra final nunca bate com o Origin de um navegador
            "https://app.example.com/app",
            "https://app.example.com?x=1",
            "https://app.example.com#top",
            "https://user@app.example.com"})
    void anythingButAnExactHttpOriginFailsStartupNamingTheEntry(String origin) {
        runner.withPropertyValues("app.cors.allowed-origins=http://localhost:8081," + origin)
                .run(context -> {
                    assertThat(context).hasFailed();
                    assertThat(context.getStartupFailure()).rootCause()
                            .isInstanceOf(IllegalArgumentException.class)
                            .hasMessageContaining("'" + origin + "'");
                });
    }

    @Configuration(proxyBeanMethods = false)
    @EnableConfigurationProperties(CorsProperties.class)
    static class CorsPropertiesConfig {
    }
}
