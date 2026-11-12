package com.yulehohenfeld.snapledger.shared.config;

import java.time.Clock;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

/**
 * One source of "now" for the whole API, so tests can replace it with a fixed clock.
 *
 * <p>PT: Uma única fonte de "agora" para a API inteira, para que os testes possam trocá-la por um
 * relógio parado.
 */
@Configuration(proxyBeanMethods = false)
public class ClockConfig {

    @Bean
    Clock clock() {
        return Clock.systemUTC();
    }
}
