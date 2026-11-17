package com.yulehohenfeld.snapledger.accountcode.repository;

import static com.yulehohenfeld.snapledger.support.LockWaits.await;
import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import java.time.Duration;
import java.time.Instant;
import java.util.UUID;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;
import java.util.stream.Stream;

import jakarta.persistence.EntityManager;
import jakarta.persistence.PersistenceException;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.Arguments;
import org.junit.jupiter.params.provider.MethodSource;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.data.jpa.test.autoconfigure.DataJpaTest;
import org.springframework.boot.jdbc.test.autoconfigure.AutoConfigureTestDatabase;
import org.springframework.boot.jpa.test.autoconfigure.TestEntityManager;
import org.springframework.context.annotation.Import;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.support.TransactionTemplate;

import com.yulehohenfeld.snapledger.accountcode.entity.CodePurpose;
import com.yulehohenfeld.snapledger.support.AccountCodeFixtures;
import com.yulehohenfeld.snapledger.support.LockWaits;
import com.yulehohenfeld.snapledger.support.TestPasswordHashes;
import com.yulehohenfeld.snapledger.support.TestcontainersConfiguration;
import com.yulehohenfeld.snapledger.user.entity.User;
import com.yulehohenfeld.snapledger.user.repository.UserRepository;

/**
 * V4 against a real PostgreSQL: mapping, the unique (user, purpose) row, every CHECK (even with the
 * application bypassed), the cascade, and the row lock that serializes issue and consume.
 *
 * <p>PT: A V4 contra um PostgreSQL real: mapeamento, a linha única (usuário, finalidade), cada CHECK
 * (mesmo contornando a aplicação), a cascata, e o lock de linha que serializa emitir e consumir.
 */
@DataJpaTest
@Import(TestcontainersConfiguration.class)
@AutoConfigureTestDatabase(replace = AutoConfigureTestDatabase.Replace.NONE)
class AccountCodeRepositoryTest {

    static final Instant NOW = Instant.parse("2026-11-17T12:00:00Z");
    static final Duration TTL = Duration.ofMinutes(15);
    static final String HASH = "a".repeat(64);

    @Autowired
    AccountCodeRepository codes;

    @Autowired
    UserRepository users;

    @Autowired
    TestEntityManager entityManager;

    @Autowired
    EntityManager jpa;

    @Autowired
    PlatformTransactionManager transactionManager;

    @Test
    void insertIfAbsentWritesTheFirstRowAndIgnoresASecond() {
        var user = newUser();

        assertThat(codes.insertIfAbsent(UUID.randomUUID(), user, "PASSWORD_RESET", HASH, NOW, NOW.plus(TTL))).isEqualTo(1);
        assertThat(codes.insertIfAbsent(UUID.randomUUID(), user, "PASSWORD_RESET", "b".repeat(64), NOW,
                NOW.plus(TTL))).isZero();
        assertThat(codes.insertIfAbsent(UUID.randomUUID(), user, "EMAIL_VERIFICATION", HASH, NOW, NOW.plus(TTL)))
                .isEqualTo(1);

        var row = codes.lock(user, CodePurpose.PASSWORD_RESET).orElseThrow();
        assertThat(row.getCodeHash()).isEqualTo(HASH);
        assertThat(row.getPurpose()).isEqualTo(CodePurpose.PASSWORD_RESET);
        assertThat(row.getAttempts()).isZero();
        assertThat(row.getUsedAt()).isNull();
        assertThat(row.getSendsInWindow()).isEqualTo(1);
        assertThat(row.getSentAt()).isEqualTo(NOW);
        assertThat(row.getExpiresAt()).isEqualTo(NOW.plus(TTL));
        assertThat(row.getWindowStartedAt()).isEqualTo(NOW);
        assertThat(row.getFailedInWindow()).isZero();
        assertThat(row.getFailedWindowStartedAt()).isNull();
        assertThat(row.isNew()).isFalse();
    }

    @Test
    void lockFindsOnlyTheRowOfThatUserAndPurpose() {
        var user = newUser();
        codes.insertIfAbsent(UUID.randomUUID(), user, "PASSWORD_RESET", HASH, NOW, NOW.plus(TTL));

        assertThat(codes.lock(user, CodePurpose.EMAIL_VERIFICATION)).isEmpty();
        assertThat(codes.lock(UUID.randomUUID(), CodePurpose.PASSWORD_RESET)).isEmpty();
    }

    @Test
    void entityChangesAreSavedByTheirIntentionMethods() {
        var user = newUser();
        codes.insertIfAbsent(UUID.randomUUID(), user, "EMAIL_VERIFICATION", HASH, NOW, NOW.plus(TTL));
        entityManager.clear();

        var row = codes.lock(user, CodePurpose.EMAIL_VERIFICATION).orElseThrow();
        row.recordFailedAttempt(NOW, Duration.ofHours(24));
        row.consume(NOW.plusSeconds(3));
        entityManager.flush();
        entityManager.clear();

        var saved = codes.lock(user, CodePurpose.EMAIL_VERIFICATION).orElseThrow();
        assertThat(saved.getAttempts()).isEqualTo(1);
        assertThat(saved.getUsedAt()).isEqualTo(NOW.plusSeconds(3));
        assertThat(saved.getFailedInWindow()).isZero();
        assertThat(saved.getFailedWindowStartedAt()).isNull();
    }

    @Test
    void aSecondRowForTheSameUserAndPurposeViolatesTheUniqueConstraint() {
        var user = newUser();
        insert(user, "PASSWORD_RESET", HASH, NOW, NOW.plus(TTL), 0, 1).executeUpdate();

        assertThatThrownBy(insert(user, "PASSWORD_RESET", HASH, NOW, NOW.plus(TTL), 0, 1)::executeUpdate)
                .isInstanceOf(PersistenceException.class)
                .rootCause().hasMessageContaining("uk_account_codes_user_purpose");
    }

    static Stream<Arguments> invalidRows() {
        return Stream.of(
                Arguments.of("ck_account_codes_purpose", "SOMETHING_ELSE", HASH, NOW.plus(TTL), 0, 1),
                Arguments.of("ck_account_codes_code_hash_hex", "PASSWORD_RESET", "A".repeat(64), NOW.plus(TTL), 0, 1),
                Arguments.of("ck_account_codes_code_hash_hex", "PASSWORD_RESET", "a".repeat(63), NOW.plus(TTL), 0, 1),
                Arguments.of("ck_account_codes_attempts_not_negative", "PASSWORD_RESET", HASH, NOW.plus(TTL), -1, 1),
                Arguments.of("ck_account_codes_sends_in_window_positive", "PASSWORD_RESET", HASH, NOW.plus(TTL), 0, 0),
                Arguments.of("ck_account_codes_expires_after_sent", "PASSWORD_RESET", HASH, NOW, 0, 1));
    }

    @ParameterizedTest(name = "{0} rejects {1} / {2}")
    @MethodSource("invalidRows")
    void eachCheckConstraintRejectsABadRowEvenWithoutTheApplication(String constraint, String purpose, String hash,
            Instant expiresAt, int attempts, int sends) {
        var user = newUser();

        assertThatThrownBy(insert(user, purpose, hash, NOW, expiresAt, attempts, sends)::executeUpdate)
                .isInstanceOf(PersistenceException.class)
                .rootCause().hasMessageContaining(constraint);
    }

    @Test
    void aNegativeFailureCountViolatesItsCheck() {
        var user = newUser();
        var query = entityManager.getEntityManager().createNativeQuery("""
                insert into account_codes (id, user_id, purpose, code_hash, sent_at, expires_at, attempts,
                                           window_started_at, sends_in_window, failed_in_window, created_at)
                values (?1, ?2, 'PASSWORD_RESET', ?3, ?4, ?5, 0, ?4, 1, -1, ?4)
                """)
                .setParameter(1, UUID.randomUUID()).setParameter(2, user).setParameter(3, HASH)
                .setParameter(4, NOW).setParameter(5, NOW.plus(TTL));

        assertThatThrownBy(query::executeUpdate).isInstanceOf(PersistenceException.class)
                .rootCause().hasMessageContaining("ck_account_codes_failed_in_window_not_negative");
    }

    @Test
    void databaseRejectsACodeOfAnUnknownUser() {
        assertThatThrownBy(insert(UUID.randomUUID(), "PASSWORD_RESET", HASH, NOW, NOW.plus(TTL), 0, 1)::executeUpdate)
                .isInstanceOf(PersistenceException.class)
                .rootCause().hasMessageContaining("fk_account_codes_user");
    }

    @Test
    void deletingTheUserDeletesItsCodes() {
        var user = newUser();
        codes.insertIfAbsent(UUID.randomUUID(), user, "PASSWORD_RESET", HASH, NOW, NOW.plus(TTL));
        codes.insertIfAbsent(UUID.randomUUID(), user, "EMAIL_VERIFICATION", HASH, NOW, NOW.plus(TTL));
        entityManager.flush();
        entityManager.clear();

        users.delete(users.findById(user).orElseThrow());
        entityManager.flush();
        entityManager.clear();

        assertThat(codes.findAll()).noneMatch(c -> c.getUserId().equals(user));
    }

    @Test
    void toStringShowsOnlyIdAndPurpose() {
        var user = UUID.randomUUID();
        var code = AccountCodeFixtures.row(user, CodePurpose.PASSWORD_RESET, HASH, NOW, TTL);

        assertThat(code.toString()).isEqualTo("AccountCode[id=" + code.getId() + ", purpose=PASSWORD_RESET]")
                .doesNotContain(HASH).doesNotContain(user.toString());
    }

    @Test
    void insertIfAbsentKeepsEntitiesAlreadyLoadedInTheTransactionAttached() {
        var user = newUser();
        var loaded = users.findById(user).orElseThrow();

        codes.insertIfAbsent(UUID.randomUUID(), user, "PASSWORD_RESET", HASH, NOW, NOW.plus(TTL));
        loaded.markEmailVerified(NOW); // a change AFTER the insert: a detached entity would lose it
        entityManager.flush();
        entityManager.clear();

        assertThat(users.findById(user).orElseThrow().getEmailVerifiedAt()).isEqualTo(NOW);
    }

    /**
     * Two requests for the same (user, purpose): the second blocks on the row lock until the first
     * commits, which is what makes the attempt counter and the single-use mark safe.
     *
     * <p>PT: Duas requisições para o mesmo (usuário, finalidade): a segunda bloqueia no lock da linha
     * até a primeira fazer commit, e é isso que torna seguros o contador de tentativas e a marca de
     * uso único.
     */
    @Test
    @Transactional(propagation = Propagation.NOT_SUPPORTED)
    void aSecondLockerWaitsForTheFirstToCommit() throws Exception {
        var tx = new TransactionTemplate(transactionManager);
        var email = "user-" + UUID.randomUUID() + "@example.com";
        ExecutorService threads = Executors.newFixedThreadPool(2);
        try {
            var user = tx.execute(status -> {
                var id = users.save(User.register("Ana", email, TestPasswordHashes.BCRYPT, "BRL", NOW)).getId();
                codes.insertIfAbsent(UUID.randomUUID(), id, "PASSWORD_RESET", HASH, NOW, NOW.plus(TTL));
                return id;
            });

            var locked = new CountDownLatch(1);
            var release = new CountDownLatch(1);
            var first = threads.submit(() -> tx.execute(status -> {
                var row = codes.lock(user, CodePurpose.PASSWORD_RESET).orElseThrow();
                row.recordFailedAttempt(NOW, Duration.ofHours(24));
                locked.countDown();
                await(release);
                return row.getAttempts();
            }));
            assertThat(locked.await(10, TimeUnit.SECONDS)).isTrue();
            var second = threads.submit(() -> tx.execute(status -> {
                var row = codes.lock(user, CodePurpose.PASSWORD_RESET).orElseThrow();
                row.recordFailedAttempt(NOW, Duration.ofHours(24));
                return row.getAttempts();
            }));
            LockWaits.awaitOneBlockedTransaction(tx, jpa);
            assertThat(second.isDone()).isFalse();
            release.countDown();

            assertThat(first.get(10, TimeUnit.SECONDS)).isEqualTo(1);
            assertThat(second.get(10, TimeUnit.SECONDS)).isEqualTo(2);
        } finally {
            threads.shutdownNow();
            tx.executeWithoutResult(status -> users.findByEmail(email).ifPresent(users::delete));
        }
    }

    private UUID newUser() {
        var user = users.save(User.register("Ana", "user-" + UUID.randomUUID() + "@example.com",
                TestPasswordHashes.BCRYPT, "BRL", NOW));
        entityManager.flush();
        return user.getId();
    }

    private jakarta.persistence.Query insert(UUID user, String purpose, String hash, Instant sentAt, Instant expiresAt,
            int attempts, int sends) {
        return entityManager.getEntityManager().createNativeQuery("""
                insert into account_codes (id, user_id, purpose, code_hash, sent_at, expires_at, attempts,
                                           window_started_at, sends_in_window, created_at)
                values (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?5, ?8, ?5)
                """)
                .setParameter(1, UUID.randomUUID())
                .setParameter(2, user)
                .setParameter(3, purpose)
                .setParameter(4, hash)
                .setParameter(5, sentAt)
                .setParameter(6, expiresAt)
                .setParameter(7, attempts)
                .setParameter(8, sends);
    }
}
