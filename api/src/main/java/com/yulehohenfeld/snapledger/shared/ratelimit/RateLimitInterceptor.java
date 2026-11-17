package com.yulehohenfeld.snapledger.shared.ratelimit;

import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;

import lombok.RequiredArgsConstructor;

import org.springframework.stereotype.Component;
import org.springframework.web.method.HandlerMethod;
import org.springframework.web.servlet.HandlerInterceptor;

import com.yulehohenfeld.snapledger.shared.error.TooManyRequestsException;

/**
 * Counts a request per client IP before the controller runs and answers
 * {@code 429 too-many-requests} past the limit of the method's {@link RateLimited} bucket. The IP
 * is the TCP peer address; {@code X-Forwarded-For} is never read because any client can forge it.
 *
 * <p>PT: Conta a requisição por IP do cliente antes do controller e responde
 * {@code 429 too-many-requests} acima do limite do bucket {@link RateLimited} do método. O IP é o
 * endereço do par TCP; o {@code X-Forwarded-For} nunca é lido, porque qualquer cliente pode forjá-lo.
 * Notes: docs/code-notes/security.md#rate-limiting
 */
@Component
@RequiredArgsConstructor
public class RateLimitInterceptor implements HandlerInterceptor {

    private final FixedWindowRateLimiter limiter;

    @Override
    public boolean preHandle(HttpServletRequest request, HttpServletResponse response, Object handler) {
        if (handler instanceof HandlerMethod method) {
            var limited = method.getMethodAnnotation(RateLimited.class);
            if (limited != null) {
                var decision = limiter.tryAcquire(limited.value(), request.getRemoteAddr());
                if (!decision.allowed()) {
                    throw new TooManyRequestsException(decision.retryAfter());
                }
            }
        }
        return true;
    }
}
