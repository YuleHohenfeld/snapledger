package com.yulehohenfeld.snapledger.shared.error;

import java.time.Duration;

import org.springframework.http.HttpStatus;

/**
 * A rate limit or a resend limit was hit; the handler sends {@code Retry-After} from
 * {@link #retryAfter()}.
 *
 * <p>PT: Um limite de requisições ou de reenvio foi atingido; o handler envia {@code Retry-After} a
 * partir de {@link #retryAfter()}.
 * Notes: docs/code-notes/security.md#rate-limiting
 */
public class TooManyRequestsException extends ApiException {

    private final Duration retryAfter;

    public TooManyRequestsException(Duration retryAfter) {
        super(HttpStatus.TOO_MANY_REQUESTS, Slugs.TOO_MANY_REQUESTS, "Too many requests. Try again later.");
        this.retryAfter = retryAfter;
    }

    public Duration retryAfter() {
        return retryAfter;
    }

    /** Whole seconds, rounded up, at least 1: a {@code Retry-After} of 0 would invite an instant retry.
     *  PT: Segundos inteiros, arredondado para cima, no mínimo 1: {@code Retry-After} 0 convidaria a tentar de novo na hora. */
    public long retryAfterSeconds() {
        var seconds = retryAfter.toSeconds() + (retryAfter.toNanosPart() > 0 ? 1 : 0);
        return Math.max(1, seconds);
    }
}
