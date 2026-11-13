package com.yulehohenfeld.snapledger.auth;

import java.time.Duration;
import java.time.Instant;

import jakarta.persistence.EntityManager;

import org.springframework.transaction.support.TransactionTemplate;

/**
 * Concurrency tests wait until PostgreSQL reports a transaction blocked on a row lock, instead of
 * sleeping and hoping the other thread got there. {@code pg_stat_activity} is the server's own view
 * of every session; {@code wait_event_type = 'Lock'} means "waiting for a lock another transaction
 * holds". Deterministic and fast; it fails loudly if the expected wait never happens.
 *
 * <p>PT: Os testes de concorrência esperam até o PostgreSQL informar uma transação bloqueada num
 * lock de linha, em vez de dormir e torcer para a outra thread ter chegado lá. O
 * {@code pg_stat_activity} é a visão do próprio servidor de todas as sessões;
 * {@code wait_event_type = 'Lock'} significa "esperando um lock que outra transação segura".
 * Determinístico e rápido; falha de forma clara se a espera esperada nunca acontecer.
 */
final class LockWaits {

    private static final Duration TIMEOUT = Duration.ofSeconds(10);

    private LockWaits() {
    }

    static void awaitOneBlockedTransaction(TransactionTemplate tx, EntityManager entityManager) {
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
}
