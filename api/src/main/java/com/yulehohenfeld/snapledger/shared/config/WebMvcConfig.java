package com.yulehohenfeld.snapledger.shared.config;

import lombok.RequiredArgsConstructor;

import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.context.annotation.Configuration;
import org.springframework.context.annotation.Import;
import org.springframework.web.servlet.config.annotation.InterceptorRegistry;
import org.springframework.web.servlet.config.annotation.WebMvcConfigurer;

import com.yulehohenfeld.snapledger.shared.ratelimit.FixedWindowRateLimiter;
import com.yulehohenfeld.snapledger.shared.ratelimit.RateLimitInterceptor;
import com.yulehohenfeld.snapledger.shared.ratelimit.RateLimitProperties;

/**
 * Registers the rate limit interceptor for the whole API. Self-contained (it imports what it
 * needs), so {@code @WebMvcTest} slices that pick it up need only a Clock.
 *
 * <p>PT: Registra o interceptor de rate limit para a API inteira. Autocontida (importa o que
 * precisa), então as fatias {@code @WebMvcTest} que a carregam só precisam de um Clock.
 * Notes: docs/code-notes/security.md#rate-limiting
 */
@Configuration(proxyBeanMethods = false)
@EnableConfigurationProperties(RateLimitProperties.class)
@Import({RateLimitInterceptor.class, FixedWindowRateLimiter.class})
@RequiredArgsConstructor
public class WebMvcConfig implements WebMvcConfigurer {

    private final RateLimitInterceptor rateLimit;

    @Override
    public void addInterceptors(InterceptorRegistry registry) {
        registry.addInterceptor(rateLimit).addPathPatterns("/api/v1/**");
    }
}
