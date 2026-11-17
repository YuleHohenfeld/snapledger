package com.yulehohenfeld.snapledger.shared.ratelimit;

import java.lang.annotation.Documented;
import java.lang.annotation.ElementType;
import java.lang.annotation.Retention;
import java.lang.annotation.RetentionPolicy;
import java.lang.annotation.Target;

/**
 * Limits a controller method per client IP, in the bucket named by {@link #value()}; the limit
 * itself lives in {@link RateLimitProperties}.
 *
 * <p>PT: Limita um método de controller por IP do cliente, no bucket indicado por {@link #value()};
 * o limite em si fica no {@link RateLimitProperties}.
 * Notes: docs/code-notes/security.md#rate-limiting
 */
@Documented
@Target(ElementType.METHOD)
@Retention(RetentionPolicy.RUNTIME)
public @interface RateLimited {

    /** A bucket name of {@link RateLimitProperties}. PT: Um nome de bucket do {@link RateLimitProperties}. */
    String value();
}
