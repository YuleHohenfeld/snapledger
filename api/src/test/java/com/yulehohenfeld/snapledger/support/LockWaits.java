package com.yulehohenfeld.snapledger.support;

import java.time.Duration;
import java.time.Instant;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;

import jakarta.persistence.EntityManager;

import org.springframework.transaction.support.TransactionTemplate;

/**
 * Coordination for concurrency tests: latches with a deadline, and waiting until PostgreSQL itself
 * reports a transaction blocked on a lock, never a sleep.
 *
 * <p>PT: Coordenação para testes de concorrência: latches com prazo, e esperar até o próprio
 * PostgreSQL informar uma transação bloqueada num lock, nunca um sleep.
 * Notes: docs/code-notes/security.md#lockwaits
 */
public final class LockWaits {

    /**
     * Must equal {@code lock_timeout} in application.properties; DatabaseConnectionSettingsTest checks it.
     *
     * <p>PT: Precisa ser igual ao {@code lock_timeout} do application.properties; o
     * DatabaseConnectionSettingsTest confere.
     */
    public static final Duration LOCK_TIMEOUT = Duration.ofSeconds(3);

    private static final Duration TIMEOUT = Duration.ofSeconds(10);

    private LockWaits() {
    }

    /**
     * Returns once {@code pg_stat_activity} shows a session waiting for a lock; fails after 10 s.
     *
     * <p>PT: Retorna assim que o {@code pg_stat_activity} mostra uma sessão esperando um lock; falha
     * depois de 10 s.
     */
    public static void awaitOneBlockedTransaction(TransactionTemplate tx, EntityManager entityManager) {
        var deadline = Instant.now().plus(TIMEOUT);
        while (Instant.now().isBefore(deadline)) {
            var waiting = tx.execute(status -> ((Number) entityManager.createNativeQuery("""
                    select count(*) from pg_stat_activity
                    where datname = current_database() and wait_event_type = 'Lock'
                    """).getSingleResult()).longValue());
            if (waiting != null && waiting > 0) {
                return;
            }
            try {
                Thread.sleep(20);
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
                throw new AssertionError("interrupted while waiting for a blocked transaction", e);
            }
        }
        throw new AssertionError("no transaction blocked on a lock within " + TIMEOUT);
    }

    /**
     * Waits for {@code latch} for at most 10 s, so a broken test fails instead of hanging.
     *
     * <p>PT: Espera o {@code latch} por no máximo 10 s, para que um teste quebrado falhe em vez de
     * travar.
     */
    public static void await(CountDownLatch latch) {
        try {
            if (!latch.await(TIMEOUT.toSeconds(), TimeUnit.SECONDS)) {
                throw new IllegalStateException("latch not released in time");
            }
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            throw new IllegalStateException(e);
        }
    }
}
