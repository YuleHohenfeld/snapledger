package com.yulehohenfeld.snapledger.shared.ratelimit;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import java.lang.reflect.Method;
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.time.ZoneOffset;

import org.junit.jupiter.api.Test;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.mock.web.MockHttpServletResponse;
import org.springframework.web.method.HandlerMethod;

import com.yulehohenfeld.snapledger.shared.error.TooManyRequestsException;

/**
 * The interceptor alone: which methods it counts, which address it keys on, and what it throws.
 *
 * <p>PT: O interceptor sozinho: quais métodos conta, em qual endereço se baseia, e o que lança.
 */
class RateLimitInterceptorTest {

    static class Handlers {

        @RateLimited(RateLimitProperties.PASSWORD_RESET)
        public void limited() {
        }

        public void free() {
        }
    }

    final Clock clock = Clock.fixed(Instant.parse("2026-11-17T12:00:00Z"), ZoneOffset.UTC);
    final FixedWindowRateLimiter limiter = new FixedWindowRateLimiter(clock,
            new RateLimitProperties(2, 20, 5, 20, Duration.ofHours(1), 100));
    final RateLimitInterceptor interceptor = new RateLimitInterceptor(limiter);
    final Handlers handlers = new Handlers();

    @Test
    void countsPerRemoteAddressAndThrowsTooManyRequestsWithTheTimeLeft() throws Exception {
        var handler = handler("limited");

        assertThat(interceptor.preHandle(request("10.0.0.1"), new MockHttpServletResponse(), handler)).isTrue();
        assertThat(interceptor.preHandle(request("10.0.0.1"), new MockHttpServletResponse(), handler)).isTrue();

        assertThatThrownBy(() -> interceptor.preHandle(request("10.0.0.1"), new MockHttpServletResponse(), handler))
                .isInstanceOfSatisfying(TooManyRequestsException.class,
                        e -> assertThat(e.retryAfter()).isEqualTo(Duration.ofHours(1)));
        assertThat(interceptor.preHandle(request("10.0.0.2"), new MockHttpServletResponse(), handler)).isTrue();
    }

    // Anyone can write X-Forwarded-For, so rotating it must not escape the limit.
    // PT: Qualquer um pode escrever o X-Forwarded-For, então girá-lo não pode escapar do limite.
    @Test
    void neverReadsForwardedHeaders() throws Exception {
        var handler = handler("limited");
        for (int i = 0; i < 2; i++) {
            var request = request("10.0.0.1");
            request.addHeader("X-Forwarded-For", "203.0.113." + i);
            request.addHeader("Forwarded", "for=198.51.100." + i);
            interceptor.preHandle(request, new MockHttpServletResponse(), handler);
        }
        var spoofed = request("10.0.0.1");
        spoofed.addHeader("X-Forwarded-For", "192.0.2.99");

        assertThatThrownBy(() -> interceptor.preHandle(spoofed, new MockHttpServletResponse(), handler))
                .isInstanceOf(TooManyRequestsException.class);
    }

    @Test
    void ignoresMethodsWithoutTheAnnotationAndNonHandlerObjects() throws Exception {
        var free = handler("free");
        for (int i = 0; i < 10; i++) {
            assertThat(interceptor.preHandle(request("10.0.0.1"), new MockHttpServletResponse(), free)).isTrue();
        }

        assertThat(interceptor.preHandle(request("10.0.0.1"), new MockHttpServletResponse(), new Object())).isTrue();
    }

    private HandlerMethod handler(String name) throws Exception {
        Method method = Handlers.class.getMethod(name);
        return new HandlerMethod(handlers, method);
    }

    private static MockHttpServletRequest request(String remoteAddr) {
        var request = new MockHttpServletRequest("POST", "/api/v1/auth/password-reset");
        request.setRemoteAddr(remoteAddr);
        return request;
    }
}
