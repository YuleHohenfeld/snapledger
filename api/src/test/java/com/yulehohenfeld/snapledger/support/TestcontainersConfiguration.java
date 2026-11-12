package com.yulehohenfeld.snapledger.support;

import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.boot.testcontainers.service.connection.ServiceConnection;
import org.springframework.context.annotation.Bean;
import org.testcontainers.postgresql.PostgreSQLContainer;

/**
 * The only database tests ever use: a throwaway PostgreSQL 17 container.
 * {@code @ServiceConnection} points the datasource at it, overriding any local .env values.
 * Spring caches contexts, so test classes with the same configuration share one container.
 *
 * <p>PT: O único banco que os testes usam: um container PostgreSQL 17 descartável. O
 * {@code @ServiceConnection} aponta o datasource para ele, sobrepondo valores do .env local. O
 * Spring guarda contextos em cache, então classes de teste com a mesma configuração compartilham
 * um container.
 */
@TestConfiguration(proxyBeanMethods = false)
public class TestcontainersConfiguration {

    @Bean
    @ServiceConnection
    PostgreSQLContainer postgres() {
        return new PostgreSQLContainer("postgres:17-alpine");
    }
}
