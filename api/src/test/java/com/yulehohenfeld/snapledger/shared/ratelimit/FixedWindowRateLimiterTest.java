package com.yulehohenfeld.snapledger.shared.ratelimit;

import static org.assertj.core.api.Assertions.assertThat;

import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.time.ZoneId;
import java.time.ZoneOffset;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.Executors;
import java.util.concurrent.atomic.AtomicInteger;

import org.junit.jupiter.api.Test;

/**
 * The counter with a movable clock: limit, rollover, isolation between keys and buckets, the key
 * cap (fail closed, purge) and thread safety.
 *
 * <p>PT: O contador com um relógio móvel: limite, virada da janela, isolamento entre chaves e
 * buckets, o teto de chaves (falha fechada, limpeza) e segurança entre threads.
 */
class FixedWindowRateLimiterTest {

    static final Instant START = Instant.parse("2026-11-17T12:00:00Z");
    static final String BUCKET = RateLimitProperties.PASSWORD_RESET;

    Instant now = START;
    final Clock clock = new Clock() {
        @Override
        public ZoneId getZone() {
            return ZoneOffset.UTC;
        }

        @Override
        public Clock withZone(ZoneId zone) {
            return this;
        }

        @Override
        public Instant instant() {
            return now;
        }
    };

    FixedWindowRateLimiter limiter(int maxKeys) {
        return new FixedWindowRateLimiter(clock,
                new RateLimitProperties(3, 20, 20, 5, 20, Duration.ofHours(1), maxKeys));
    }

    @Test
    void allowsUpToTheLimitThenRefusesWithTheTimeLeftInTheWindow() {
        var limiter = limiter(100);

        for (int i = 0; i < 3; i++) {
            assertThat(limiter.tryAcquire(BUCKET, "ip").allowed()).isTrue();
        }
        now = START.plus(Duration.ofMinutes(20));
        var refused = limiter.tryAcquire(BUCKET, "ip");

        assertThat(refused.allowed()).isFalse();
        assertThat(refused.retryAfter()).isEqualTo(Duration.ofMinutes(40));
    }

    @Test
    void theWindowRollsOverExactlyWhenItEnds() {
        var limiter = limiter(100);
        for (int i = 0; i < 3; i++) {
            limiter.tryAcquire(BUCKET, "ip");
        }

        now = START.plus(Duration.ofHours(1)).minusSeconds(1);
        assertThat(limiter.tryAcquire(BUCKET, "ip").allowed()).isFalse();

        now = START.plus(Duration.ofHours(1));
        assertThat(limiter.tryAcquire(BUCKET, "ip").allowed()).isTrue();
        assertThat(limiter.tryAcquire(BUCKET, "ip").allowed()).isTrue();
        assertThat(limiter.tryAcquire(BUCKET, "ip").allowed()).isTrue();
        assertThat(limiter.tryAcquire(BUCKET, "ip").allowed()).isFalse();
    }

    @Test
    void keysAndBucketsAreIsolated() {
        var limiter = limiter(100);
        for (int i = 0; i < 3; i++) {
            limiter.tryAcquire(BUCKET, "ip-a");
        }

        assertThat(limiter.tryAcquire(BUCKET, "ip-a").allowed()).isFalse();
        assertThat(limiter.tryAcquire(BUCKET, "ip-b").allowed()).isTrue();
        assertThat(limiter.tryAcquire(RateLimitProperties.PASSWORD_RESET_CONFIRM, "ip-a").allowed()).isTrue();
    }

    @Test
    void eachBucketUsesItsOwnLimit() {
        var limiter = limiter(100);

        for (int i = 0; i < 20; i++) {
            assertThat(limiter.tryAcquire(RateLimitProperties.PASSWORD_RESET_CONFIRM, "ip").allowed()).isTrue();
        }
        assertThat(limiter.tryAcquire(RateLimitProperties.PASSWORD_RESET_CONFIRM, "ip").allowed()).isFalse();
        for (int i = 0; i < 5; i++) {
            assertThat(limiter.tryAcquire(RateLimitProperties.PASSWORD_RESET_EMAIL, "e").allowed()).isTrue();
        }
        assertThat(limiter.tryAcquire(RateLimitProperties.PASSWORD_RESET_EMAIL, "e").allowed()).isFalse();
    }

    // Fail closed: when the table is full of live windows, an unknown key is refused instead of
    // growing memory; keys already tracked keep working.
    // PT: Falha fechada: com a tabela cheia de janelas vivas, uma chave desconhecida é recusada em vez de
    //     crescer a memória; as chaves já rastreadas continuam funcionando.
    @Test
    void aFullTableRefusesNewKeysButKeepsServingTrackedOnes() {
        var limiter = limiter(2);
        assertThat(limiter.tryAcquire(BUCKET, "a").allowed()).isTrue();
        assertThat(limiter.tryAcquire(BUCKET, "b").allowed()).isTrue();

        var refused = limiter.tryAcquire(BUCKET, "c");

        assertThat(refused.allowed()).isFalse();
        assertThat(refused.retryAfter()).isPositive();
        assertThat(limiter.tryAcquire(BUCKET, "a").allowed()).isTrue();
    }

    @Test
    void expiredWindowsArePurgedWhenTheTableIsFull() {
        var limiter = limiter(2);
        limiter.tryAcquire(BUCKET, "a");
        limiter.tryAcquire(BUCKET, "b");

        now = START.plus(Duration.ofHours(1));

        assertThat(limiter.tryAcquire(BUCKET, "c").allowed()).isTrue();
        assertThat(limiter.tryAcquire(BUCKET, "d").allowed()).isTrue();
        assertThat(limiter.tryAcquire(BUCKET, "e").allowed()).isFalse();
    }

    @Test
    void concurrentCallsNeverAdmitMoreThanTheLimit() throws Exception {
        var limiter = limiter(100);
        var admitted = new AtomicInteger();
        var start = new CountDownLatch(1);
        var pool = Executors.newFixedThreadPool(16);
        try {
            var futures = new java.util.ArrayList<java.util.concurrent.Future<?>>();
            for (int i = 0; i < 64; i++) {
                futures.add(pool.submit(() -> {
                    start.await();
                    if (limiter.tryAcquire(BUCKET, "ip").allowed()) {
                        admitted.incrementAndGet();
                    }
                    return null;
                }));
            }
            start.countDown();
            for (var future : futures) {
                future.get();
            }
        } finally {
            pool.shutdownNow();
        }

        assertThat(admitted.get()).isEqualTo(3);
    }

    @Test
    void anUnknownBucketIsAProgrammingError() {
        var limiter = limiter(100);

        org.assertj.core.api.Assertions.assertThatThrownBy(() -> limiter.tryAcquire("made-up", "ip"))
                .isInstanceOf(IllegalArgumentException.class);
    }
}
