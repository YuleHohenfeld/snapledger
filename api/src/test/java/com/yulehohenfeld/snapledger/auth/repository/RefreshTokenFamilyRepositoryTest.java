package com.yulehohenfeld.snapledger.auth.repository;

import static com.yulehohenfeld.snapledger.support.LockWaits.LOCK_TIMEOUT;
import static com.yulehohenfeld.snapledger.support.LockWaits.await;
import static com.yulehohenfeld.snapledger.support.TestTokenHashes.hashOf;
import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.assertj.core.api.Assertions.catchThrowable;

import java.time.Duration;
import java.time.Instant;
import java.util.UUID;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutionException;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;

import jakarta.persistence.EntityManager;
import jakarta.persistence.PersistenceException;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.data.jpa.test.autoconfigure.DataJpaTest;
import org.springframework.boot.jdbc.test.autoconfigure.AutoConfigureTestDatabase;
import org.springframework.boot.jpa.test.autoconfigure.TestEntityManager;
import org.springframework.context.annotation.Import;
import org.springframework.dao.PessimisticLockingFailureException;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.support.TransactionTemplate;

import com.yulehohenfeld.snapledger.auth.entity.RefreshToken;
import com.yulehohenfeld.snapledger.auth.entity.RefreshTokenFamily;
import com.yulehohenfeld.snapledger.shared.error.ApiException;
import com.yulehohenfeld.snapledger.support.LockWaits;
import com.yulehohenfeld.snapledger.support.TestPasswordHashes;
import com.yulehohenfeld.snapledger.support.TestcontainersConfiguration;
import com.yulehohenfeld.snapledger.user.entity.User;
import com.yulehohenfeld.snapledger.user.repository.UserRepository;

/**
 * The refresh_token_families table of V2 and the serialization between rotation and revocation
 * (ADR 0008), with real concurrent transactions on a real PostgreSQL (READ COMMITTED, its default).
 *
 * <p>PT: A tabela refresh_token_families da V2 e a serialização entre rotação e revogação (ADR
 * 0008), com transações concorrentes reais num PostgreSQL real (READ COMMITTED, o padrão dele).
 */
@DataJpaTest
@Import(TestcontainersConfiguration.class)
@AutoConfigureTestDatabase(replace = AutoConfigureTestDatabase.Replace.NONE)
class RefreshTokenFamilyRepositoryTest {

    static final Instant NOW = Instant.parse("2026-11-12T10:00:00Z");
    static final Duration TTL = Duration.ofDays(30);

    // The wait was already running when the poll saw it (up to one 20 ms poll plus a query), so the
    // measured time may be a little under LOCK_TIMEOUT; the upper slack absorbs a slow CI machine.
    // PT: A espera já corria quando a sondagem a viu (até uma sondagem de 20 ms mais uma query), então
    //     o tempo medido pode ficar um pouco abaixo do LOCK_TIMEOUT; a folga de cima absorve uma CI lenta.
    static final Duration SLACK_BEFORE = Duration.ofMillis(500);
    static final Duration SLACK = Duration.ofSeconds(5);

    @Autowired
    RefreshTokenFamilyRepository families;

    @Autowired
    RefreshTokenRepository tokens;

    @Autowired
    UserRepository users;

    @Autowired
    TestEntityManager entityManager;

    // The shared, transaction-bound EntityManager; usable from any thread inside a TransactionTemplate.
    // PT: O EntityManager compartilhado, ligado à transação; usável de qualquer thread dentro de um TransactionTemplate.
    @Autowired
    EntityManager jpa;

    @Autowired
    PlatformTransactionManager transactionManager;

    @Test
    void savesAFamilyAndLocksItWhileItIsActive() {
        var user = newUser(uniqueEmail());
        var family = families.save(RefreshTokenFamily.start(user, NOW));
        entityManager.flush();
        entityManager.clear();

        var locked = families.lockActive(family.getId()).orElseThrow();

        assertThat(locked.getUserId()).isEqualTo(user);
        assertThat(locked.getCreatedAt()).isEqualTo(NOW);
        assertThat(locked.getRevokedAt()).isNull();
        assertThat(locked.isNew()).isFalse();
        assertThat(families.lockActive(UUID.randomUUID())).isEmpty();
    }

    @Test
    void revokeSucceedsOnceAndKeepsTheFirstRevocationTime() {
        var family = newFamily(uniqueEmail());

        assertThat(families.revoke(family, NOW.plusSeconds(5))).isEqualTo(1);
        assertThat(families.revoke(family, NOW.plusSeconds(9))).isZero();
        assertThat(families.revoke(UUID.randomUUID(), NOW)).isZero();

        assertThat(families.findById(family).orElseThrow().getRevokedAt()).isEqualTo(NOW.plusSeconds(5));
    }

    // Revoking one session leaves the user's other sessions (other devices) alive.
    // PT: Revogar uma sessão deixa as outras sessões do usuário (outros aparelhos) vivas.
    @Test
    void revokeTouchesOnlyThatFamily() {
        var user = newUser(uniqueEmail());
        var revoked = families.save(RefreshTokenFamily.start(user, NOW)).getId();
        var other = families.save(RefreshTokenFamily.start(user, NOW)).getId();
        var otherToken = tokens.save(RefreshToken.issue(other, hashOf("other"), NOW, NOW.plus(TTL)));

        families.revoke(revoked, NOW.plusSeconds(1));

        assertThat(families.lockActive(other)).isPresent();
        assertThat(tokens.markUsed(otherToken.getId(), NOW.plusSeconds(2))).isEqualTo(1);
    }

    // A rotation that starts after the revocation committed: the lock finds no active family and the
    // token cannot be consumed either.
    // PT: Uma rotação que começa depois de a revogação fazer commit: o lock não encontra família ativa
    //     e o token também não pode ser consumido.
    @Test
    void rotationAfterRevocationFindsNoActiveFamily() {
        var family = newFamily(uniqueEmail());
        var token = tokens.save(RefreshToken.issue(family, hashOf("raw"), NOW, NOW.plus(TTL)));
        families.revoke(family, NOW.plusSeconds(1));

        assertThat(families.lockActive(family)).isEmpty();
        assertThat(tokens.markUsed(token.getId(), NOW.plusSeconds(2))).isZero();
    }

    @Test
    void deletingTheUserDeletesItsFamiliesAndTheirTokens() {
        var email = uniqueEmail();
        var family = newFamily(email);
        var token = tokens.save(RefreshToken.issue(family, hashOf("raw"), NOW, NOW.plus(TTL)));
        entityManager.flush();
        entityManager.clear();

        users.delete(users.findByEmail(email).orElseThrow());
        entityManager.flush();
        entityManager.clear();

        assertThat(families.findById(family)).isEmpty();
        assertThat(tokens.findById(token.getId())).isEmpty();
    }

    @Test
    void databaseRejectsAFamilyOfAnUnknownUser() {
        var insert = entityManager.getEntityManager().createNativeQuery("""
                insert into refresh_token_families (id, user_id, created_at) values (?1, ?2, ?3)
                """)
                .setParameter(1, UUID.randomUUID())
                .setParameter(2, UUID.randomUUID())
                .setParameter(3, NOW);

        assertThatThrownBy(insert::executeUpdate)
                .isInstanceOf(PersistenceException.class)
                .rootCause().hasMessageContaining("fk_refresh_token_families_user");
    }

    @Test
    void toStringShowsOnlyIds() {
        var user = UUID.randomUUID();
        var family = RefreshTokenFamily.start(user, NOW);

        assertThat(family.toString()).isEqualTo("RefreshTokenFamily[id=" + family.getId() + ", userId=" + user + "]");
    }

    /**
     * The race of ADR 0008. A rotation has locked the family, consumed Tn and inserted Tn+1, and is
     * still open. A logout (or a reuse elsewhere) revokes the family now. Without the family row,
     * a per-token revoke under READ COMMITTED could not see the uncommitted Tn+1 and it would
     * survive. Here the revocation blocks on the family row until the rotation commits, and
     * afterwards Tn+1 is dead.
     *
     * <p>PT: A disputa da ADR 0008. Uma rotação travou a família, consumiu o Tn e inseriu o Tn+1, e
     * continua aberta. Um logout (ou um reuso em outro lugar) revoga a família agora. Sem a linha
     * da família, uma revogação por token em READ COMMITTED não enxergaria o Tn+1 ainda sem commit,
     * e ele sobreviveria. Aqui a revogação fica bloqueada na linha da família até a rotação fazer
     * commit, e depois disso o Tn+1 está morto.
     */
    @Test
    @Transactional(propagation = Propagation.NOT_SUPPORTED)
    void revocationDuringARotationWaitsAndThenKillsTheNewToken() throws Exception {
        var tx = new TransactionTemplate(transactionManager);
        var email = uniqueEmail();
        ExecutorService threads = Executors.newFixedThreadPool(2);
        try {
            var family = tx.execute(status -> newFamily(email));
            var current = tx.execute(status -> tokens.save(
                    RefreshToken.issue(family, hashOf("tn"), NOW, NOW.plus(TTL))).getId());

            var inserted = new CountDownLatch(1);
            var release = new CountDownLatch(1);
            var rotation = threads.submit(() -> tx.execute(status -> {
                families.lockActive(family).orElseThrow();
                assertThat(tokens.markUsed(current, NOW.plusSeconds(1))).isEqualTo(1);
                var next = tokens.saveAndFlush(RefreshToken.issue(family, hashOf("tn+1"), NOW.plusSeconds(1),
                        NOW.plusSeconds(1).plus(TTL))).getId();
                inserted.countDown();
                await(release); // still open: Tn+1 is inserted but not committed
                // PT: ainda aberta: o Tn+1 está inserido mas sem commit
                return next;
            }));
            assertThat(inserted.await(10, TimeUnit.SECONDS)).isTrue();
            var revocation = threads.submit(() -> tx.execute(status -> families.revoke(family, NOW.plusSeconds(5))));
            LockWaits.awaitOneBlockedTransaction(tx, jpa); // the revocation waits for the family row
            // PT: a revogação espera pela linha da família
            release.countDown();

            var next = rotation.get(10, TimeUnit.SECONDS);
            assertThat(revocation.get(10, TimeUnit.SECONDS)).isEqualTo(1);
            Integer nextConsumed = tx.execute(status -> tokens.markUsed(next, NOW.plusSeconds(6)));
            Boolean stillActive = tx.execute(status -> families.lockActive(family).isPresent());
            Instant revokedAt = tx.execute(status -> families.findById(family).orElseThrow().getRevokedAt());
            assertThat(nextConsumed).isZero();
            assertThat(stillActive).isFalse();
            assertThat(revokedAt).isEqualTo(NOW.plusSeconds(5));
        } finally {
            threads.shutdownNow();
            cleanUp(tx, email);
        }
    }

    /**
     * The other order: the revocation holds the family row when a rotation arrives. The rotation's
     * lock waits; when the revocation commits, PostgreSQL re-checks {@code revoked_at is null} on
     * the new row version and returns nothing, so the rotation cannot issue a token.
     *
     * <p>PT: A outra ordem: a revogação segura a linha da família quando uma rotação chega. O lock da
     * rotação espera; quando a revogação faz commit, o PostgreSQL reavalia {@code revoked_at is null}
     * na nova versão da linha e não devolve nada, então a rotação não consegue emitir um token.
     */
    @Test
    @Transactional(propagation = Propagation.NOT_SUPPORTED)
    void rotationThatWaitsForARevocationFindsTheFamilyRevoked() throws Exception {
        var tx = new TransactionTemplate(transactionManager);
        var email = uniqueEmail();
        ExecutorService threads = Executors.newFixedThreadPool(2);
        try {
            var family = tx.execute(status -> newFamily(email));

            var revoked = new CountDownLatch(1);
            var release = new CountDownLatch(1);
            var revocation = threads.submit(() -> tx.execute(status -> {
                var rows = families.revoke(family, NOW.plusSeconds(5));
                revoked.countDown();
                await(release); // keep the family row locked, revocation not committed yet
                // PT: mantém a linha da família travada, revogação ainda sem commit
                return rows;
            }));
            assertThat(revoked.await(10, TimeUnit.SECONDS)).isTrue();
            var rotation = threads.submit(() -> tx.execute(status -> families.lockActive(family).isPresent()));
            LockWaits.awaitOneBlockedTransaction(tx, jpa); // the rotation waits for the family row
            // PT: a rotação espera pela linha da família
            release.countDown();

            assertThat(revocation.get(10, TimeUnit.SECONDS)).isEqualTo(1);
            assertThat(rotation.get(10, TimeUnit.SECONDS)).isFalse();
        } finally {
            threads.shutdownNow();
            cleanUp(tx, email);
        }
    }

    /**
     * A family row held past lock_timeout: the waiter fails with a database error (masked 500), never an ApiException.
     *
     * <p>PT: Uma linha de família segurada além do lock_timeout: quem espera falha com um erro de
     * banco (500 mascarado), nunca uma ApiException.
     * Notes: docs/code-notes/security.md#lock_timeout
     */
    @Test
    @Transactional(propagation = Propagation.NOT_SUPPORTED)
    void aFamilyLockHeldPastTheTimeoutFailsTheWaiterWithADatabaseError() throws Exception {
        var tx = new TransactionTemplate(transactionManager);
        var email = uniqueEmail();
        ExecutorService threads = Executors.newFixedThreadPool(2);
        var release = new CountDownLatch(1);
        try {
            var family = tx.execute(status -> newFamily(email));
            var locked = new CountDownLatch(1);
            var holder = threads.submit(() -> tx.execute(status -> {
                families.lockActive(family).orElseThrow();
                locked.countDown();
                await(release);
                return null;
            }));
            assertThat(locked.await(10, TimeUnit.SECONDS)).isTrue();

            var waiter = threads.submit(() -> tx.execute(status -> families.lockActive(family)));
            // Timing starts once PostgreSQL reports the wait, so thread start-up is not measured.
            // PT: A medição começa quando o PostgreSQL informa a espera, então a partida da thread não conta.
            LockWaits.awaitOneBlockedTransaction(tx, jpa);
            var started = System.nanoTime();
            var failure = catchThrowable(() -> waiter.get(LOCK_TIMEOUT.plus(SLACK).toSeconds(), TimeUnit.SECONDS));
            var waited = Duration.ofNanos(System.nanoTime() - started);

            assertThat(failure).isInstanceOf(ExecutionException.class);
            assertThat(failure.getCause())
                    .isInstanceOf(PessimisticLockingFailureException.class)
                    .isNotInstanceOf(ApiException.class);
            assertThat(waited).isBetween(LOCK_TIMEOUT.minus(SLACK_BEFORE), LOCK_TIMEOUT.plus(SLACK));
            release.countDown();
            holder.get(10, TimeUnit.SECONDS);
        } finally {
            release.countDown();
            threads.shutdownNow();
            cleanUp(tx, email);
        }
    }

    private UUID newUser(String email) {
        return users.save(User.register("Ana", email, TestPasswordHashes.BCRYPT, "BRL", NOW)).getId();
    }

    private UUID newFamily(String email) {
        return families.save(RefreshTokenFamily.start(newUser(email), NOW)).getId();
    }

    // Deleting the user cascades to its families and their tokens.
    // PT: Apagar o usuário propaga em cascata para as famílias dele e os tokens delas.
    private void cleanUp(TransactionTemplate tx, String email) {
        tx.executeWithoutResult(status -> users.findByEmail(email).ifPresent(users::delete));
    }

    private static String uniqueEmail() {
        return "user-" + UUID.randomUUID() + "@example.com";
    }
}
