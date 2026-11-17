package com.yulehohenfeld.snapledger.auth.repository;

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

import com.yulehohenfeld.snapledger.support.LockWaits;
import com.yulehohenfeld.snapledger.support.PasswordResetGrantFixtures;
import com.yulehohenfeld.snapledger.support.TestPasswordHashes;
import com.yulehohenfeld.snapledger.support.TestcontainersConfiguration;
import com.yulehohenfeld.snapledger.user.entity.User;
import com.yulehohenfeld.snapledger.user.repository.UserRepository;

/**
 * V5 against a real PostgreSQL: mapping, the upsert that replaces a user's grant, every constraint
 * (even with the application bypassed), the cascade, and the row lock confirm takes.
 *
 * <p>PT: A V5 contra um PostgreSQL real: mapeamento, o upsert que substitui a permissão do usuário,
 * cada constraint (mesmo contornando a aplicação), a cascata, e o lock de linha que o confirm toma.
 * Notes: docs/code-notes/auth.md#v5__create_password_reset_grants
 */
@DataJpaTest
@Import(TestcontainersConfiguration.class)
@AutoConfigureTestDatabase(replace = AutoConfigureTestDatabase.Replace.NONE)
class PasswordResetGrantRepositoryTest {

    static final Instant NOW = Instant.parse("2026-11-17T12:00:00Z");
    static final Instant EXPIRES = NOW.plus(Duration.ofMinutes(10));
    static final String HASH = "a".repeat(64);
    static final String OTHER_HASH = "b".repeat(64);

    @Autowired
    PasswordResetGrantRepository grants;

    @Autowired
    UserRepository users;

    @Autowired
    TestEntityManager entityManager;

    @Autowired
    EntityManager jpa;

    @Autowired
    PlatformTransactionManager transactionManager;

    @Test
    void upsertWritesTheGrantAndItIsFoundByHashWithAndWithoutALock() {
        var user = newUser();

        assertThat(grants.upsert(UUID.randomUUID(), user, HASH, EXPIRES, NOW)).isEqualTo(1);

        assertThat(grants.findUserIdByTokenHash(HASH)).contains(user);
        var row = grants.lockByTokenHash(HASH).orElseThrow();
        assertThat(row.getUserId()).isEqualTo(user);
        assertThat(row.getExpiresAt()).isEqualTo(EXPIRES);
        assertThat(row.getCreatedAt()).isEqualTo(NOW);
        assertThat(row.getUsedAt()).isNull();
        assertThat(row.isNew()).isFalse();
        assertThat(grants.findUserIdByTokenHash(OTHER_HASH)).isEmpty();
        assertThat(grants.lockByTokenHash(OTHER_HASH)).isEmpty();
    }

    @Test
    void aSecondUpsertReplacesTheGrantAndClearsTheUseMark() {
        var user = newUser();
        grants.upsert(UUID.randomUUID(), user, HASH, EXPIRES, NOW);
        grants.lockByTokenHash(HASH).orElseThrow().markUsed(NOW.plusSeconds(1));
        entityManager.flush();

        grants.upsert(UUID.randomUUID(), user, OTHER_HASH, EXPIRES.plusSeconds(60), NOW.plusSeconds(60));

        assertThat(grants.findUserIdByTokenHash(HASH)).isEmpty();
        var row = grants.lockByTokenHash(OTHER_HASH).orElseThrow();
        assertThat(row.getUsedAt()).isNull();
        assertThat(row.getExpiresAt()).isEqualTo(EXPIRES.plusSeconds(60));
        assertThat(grants.findAll()).filteredOn(g -> g.getUserId().equals(user)).hasSize(1);
    }

    @Test
    void markUsedIsSavedAndEndsTheUsability() {
        var user = newUser();
        grants.upsert(UUID.randomUUID(), user, HASH, EXPIRES, NOW);
        var row = grants.lockByTokenHash(HASH).orElseThrow();
        assertThat(row.isUsable(NOW)).isTrue();
        assertThat(row.isUsable(EXPIRES)).isFalse();

        row.markUsed(NOW.plusSeconds(3));
        entityManager.flush();
        entityManager.clear();

        var saved = grants.lockByTokenHash(HASH).orElseThrow();
        assertThat(saved.getUsedAt()).isEqualTo(NOW.plusSeconds(3));
        assertThat(saved.isUsable(NOW.plusSeconds(4))).isFalse();
    }

    @Test
    void aSecondRowForTheSameUserViolatesTheUniqueUser() {
        var user = newUser();
        insert(user, HASH, NOW, EXPIRES).executeUpdate();

        assertThatThrownBy(insert(user, OTHER_HASH, NOW, EXPIRES)::executeUpdate)
                .isInstanceOf(PersistenceException.class)
                .rootCause().hasMessageContaining("uk_password_reset_grants_user");
    }

    @Test
    void aRepeatedHashViolatesTheUniqueHashEvenWithoutTheApplication() {
        insert(newUser(), HASH, NOW, EXPIRES).executeUpdate();

        assertThatThrownBy(insert(newUser(), HASH, NOW, EXPIRES)::executeUpdate)
                .isInstanceOf(PersistenceException.class)
                .rootCause().hasMessageContaining("uk_password_reset_grants_token_hash");
    }

    static Stream<Arguments> invalidRows() {
        return Stream.of(
                Arguments.of("ck_password_reset_grants_token_hash_hex", "A".repeat(64), EXPIRES),
                Arguments.of("ck_password_reset_grants_token_hash_hex", "a".repeat(63), EXPIRES),
                Arguments.of("ck_password_reset_grants_token_hash_hex", "g".repeat(64), EXPIRES),
                Arguments.of("ck_password_reset_grants_expires_after_created", HASH, NOW));
    }

    @ParameterizedTest(name = "{0} rejects {1} / {2}")
    @MethodSource("invalidRows")
    void eachCheckConstraintRejectsABadRowEvenWithoutTheApplication(String constraint, String hash, Instant expiresAt) {
        var user = newUser();

        assertThatThrownBy(insert(user, hash, NOW, expiresAt)::executeUpdate)
                .isInstanceOf(PersistenceException.class)
                .rootCause().hasMessageContaining(constraint);
    }

    @Test
    void databaseRejectsAGrantOfAnUnknownUser() {
        assertThatThrownBy(insert(UUID.randomUUID(), HASH, NOW, EXPIRES)::executeUpdate)
                .isInstanceOf(PersistenceException.class)
                .rootCause().hasMessageContaining("fk_password_reset_grants_user");
    }

    @Test
    void deletingTheUserDeletesItsGrant() {
        var user = newUser();
        grants.upsert(UUID.randomUUID(), user, HASH, EXPIRES, NOW);
        entityManager.flush();
        entityManager.clear();

        users.delete(users.findById(user).orElseThrow());
        entityManager.flush();
        entityManager.clear();

        assertThat(grants.findUserIdByTokenHash(HASH)).isEmpty();
    }

    @Test
    void toStringNeverShowsTheHashOrTheUser() {
        var user = UUID.randomUUID();
        var grant = PasswordResetGrantFixtures.row(user, HASH, NOW, EXPIRES, null);

        assertThat(grant.toString()).isEqualTo("PasswordResetGrant[id=" + grant.getId() + "]")
                .doesNotContain(HASH).doesNotContain(user.toString());
    }

    /**
     * Two confirms with the same token: the second blocks on the grant row until the first commits,
     * which is what makes the single-use mark safe.
     *
     * <p>PT: Dois confirms com o mesmo token: o segundo bloqueia na linha da permissão até o primeiro
     * fazer commit, e é isso que torna seguro o uso único.
     */
    @Test
    @Transactional(propagation = Propagation.NOT_SUPPORTED)
    void aSecondLockerWaitsForTheFirstToCommit() throws Exception {
        var tx = new TransactionTemplate(transactionManager);
        var email = "user-" + UUID.randomUUID() + "@example.com";
        ExecutorService threads = Executors.newFixedThreadPool(2);
        try {
            var hash = UUID.randomUUID().toString().replace("-", "").repeat(2);
            tx.executeWithoutResult(status -> {
                var id = users.save(User.register("Ana", email, TestPasswordHashes.BCRYPT, "BRL", NOW)).getId();
                grants.upsert(UUID.randomUUID(), id, hash, EXPIRES, NOW);
            });

            var locked = new CountDownLatch(1);
            var release = new CountDownLatch(1);
            var first = threads.submit(() -> tx.execute(status -> {
                var row = grants.lockByTokenHash(hash).orElseThrow();
                var usable = row.isUsable(NOW);
                row.markUsed(NOW);
                locked.countDown();
                await(release);
                return usable;
            }));
            assertThat(locked.await(10, TimeUnit.SECONDS)).isTrue();
            var second = threads.submit(() -> tx.execute(status -> grants.lockByTokenHash(hash).orElseThrow()
                    .isUsable(NOW)));
            LockWaits.awaitOneBlockedTransaction(tx, jpa);
            assertThat(second.isDone()).isFalse();
            release.countDown();

            assertThat(first.get(10, TimeUnit.SECONDS)).isTrue();
            assertThat(second.get(10, TimeUnit.SECONDS)).isFalse();
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

    private jakarta.persistence.Query insert(UUID user, String hash, Instant createdAt, Instant expiresAt) {
        return entityManager.getEntityManager().createNativeQuery("""
                insert into password_reset_grants (id, user_id, token_hash, expires_at, created_at)
                values (?1, ?2, ?3, ?4, ?5)
                """)
                .setParameter(1, UUID.randomUUID())
                .setParameter(2, user)
                .setParameter(3, hash)
                .setParameter(4, expiresAt)
                .setParameter(5, createdAt);
    }
}
