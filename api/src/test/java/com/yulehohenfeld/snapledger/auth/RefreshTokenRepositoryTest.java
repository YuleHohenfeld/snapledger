package com.yulehohenfeld.snapledger.auth;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.time.Duration;
import java.time.Instant;
import java.util.HexFormat;
import java.util.UUID;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;

import jakarta.persistence.EntityManager;
import jakarta.persistence.PersistenceException;
import jakarta.persistence.Query;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.data.jpa.test.autoconfigure.DataJpaTest;
import org.springframework.boot.jdbc.test.autoconfigure.AutoConfigureTestDatabase;
import org.springframework.boot.jpa.test.autoconfigure.TestEntityManager;
import org.springframework.context.annotation.Import;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.support.TransactionTemplate;

import com.yulehohenfeld.snapledger.support.TestPasswordHashes;
import com.yulehohenfeld.snapledger.support.TestcontainersConfiguration;
import com.yulehohenfeld.snapledger.user.User;
import com.yulehohenfeld.snapledger.user.UserRepository;

/**
 * The refresh_tokens table of V2 and the atomic markUsed of ADR 0002 against a real PostgreSQL.
 * Families and the revocation race are in RefreshTokenFamilyRepositoryTest.
 *
 * <p>PT: A tabela refresh_tokens da V2 e o markUsed atômico da ADR 0002 contra um PostgreSQL real.
 * As famílias e a disputa com a revogação estão no RefreshTokenFamilyRepositoryTest.
 */
@DataJpaTest
@Import(TestcontainersConfiguration.class)
@AutoConfigureTestDatabase(replace = AutoConfigureTestDatabase.Replace.NONE)
class RefreshTokenRepositoryTest {

    static final Instant NOW = Instant.parse("2026-11-12T10:00:00Z");
    static final Duration TTL = Duration.ofDays(30);

    @Autowired
    RefreshTokenRepository tokens;

    @Autowired
    RefreshTokenFamilyRepository families;

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
    void findsATokenByItsHash() {
        var family = newFamily();
        var hash = hashOf("raw-1");
        var saved = tokens.save(RefreshToken.issue(family, hash, NOW, NOW.plus(TTL)));
        entityManager.flush();
        entityManager.clear();

        var found = tokens.findByTokenHash(hash).orElseThrow();

        assertThat(found.getId()).isEqualTo(saved.getId());
        assertThat(found.getFamilyId()).isEqualTo(family);
        assertThat(found.getExpiresAt()).isEqualTo(NOW.plus(TTL));
        assertThat(found.getUsedAt()).isNull();
        assertThat(found.isNew()).isFalse();
        assertThat(tokens.findByTokenHash(hashOf("raw-2"))).isEmpty();
    }

    @Test
    void markUsedSucceedsOnceThenReportsReuse() {
        var token = tokens.save(RefreshToken.issue(newFamily(), hashOf("raw"), NOW, NOW.plus(TTL)));

        assertThat(tokens.markUsed(token.getId(), NOW.plusSeconds(1))).isEqualTo(1);
        assertThat(tokens.markUsed(token.getId(), NOW.plusSeconds(2))).isZero();

        // clearAutomatically: the next read comes from the database, not from a stale cached copy.
        // PT: clearAutomatically: a próxima leitura vem do banco, e não de uma cópia desatualizada em cache.
        assertThat(tokens.findById(token.getId()).orElseThrow().getUsedAt()).isEqualTo(NOW.plusSeconds(1));
    }

    @Test
    void markUsedOfATokenOfARevokedFamilyChangesNothing() {
        var family = newFamily();
        var token = tokens.save(RefreshToken.issue(family, hashOf("raw"), NOW, NOW.plus(TTL)));
        families.revoke(family, NOW);

        assertThat(tokens.markUsed(token.getId(), NOW.plusSeconds(1))).isZero();
        assertThat(tokens.findById(token.getId()).orElseThrow().getUsedAt()).isNull();
    }

    // Expiry is exclusive: at exactly expires_at the token is already dead. The service checks
    // expiry before markUsed, so that this 0 is answered as "expired", never as reuse.
    // PT: A expiração é exclusiva: exatamente em expires_at o token já está morto. O Service confere
    //     a expiração antes do markUsed, para que este 0 seja respondido como "vencido", nunca como reuso.
    @Test
    void markUsedOfAnExpiredTokenChangesNothing() {
        var token = tokens.save(RefreshToken.issue(newFamily(), hashOf("raw"), NOW, NOW.plus(TTL)));

        assertThat(tokens.markUsed(token.getId(), NOW.plus(TTL))).isZero();
        assertThat(tokens.markUsed(token.getId(), NOW.plus(TTL).plusSeconds(1))).isZero();
        assertThat(tokens.findById(token.getId()).orElseThrow().getUsedAt()).isNull();
        assertThat(tokens.markUsed(token.getId(), NOW.plus(TTL).minusMillis(1))).isEqualTo(1);
    }

    @Test
    void toStringNeverShowsTheHash() {
        var hash = hashOf("raw");
        var token = RefreshToken.issue(UUID.randomUUID(), hash, NOW, NOW.plus(TTL));

        assertThat(token.toString()).contains(token.getId().toString()).doesNotContain(hash);
    }

    @Test
    void duplicateHashViolatesTheUniqueConstraint() {
        var family = newFamily();
        tokens.saveAndFlush(RefreshToken.issue(family, hashOf("same"), NOW, NOW.plus(TTL)));

        assertThatThrownBy(() -> tokens.saveAndFlush(RefreshToken.issue(family, hashOf("same"), NOW, NOW.plus(TTL))))
                .rootCause().hasMessageContaining("uk_refresh_tokens_token_hash");
    }

    @ParameterizedTest
    @ValueSource(strings = {
            "ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789", // uppercase hex
            // PT: hexadecimal em maiúsculas
            "abcdef0123456789abcdef0123456789abcdef0123456789abcdef012345678",  // 63 characters
            // PT: 63 caracteres
            "zzzzzz0123456789abcdef0123456789abcdef0123456789abcdef0123456789"  // not hex
            // PT: não é hexadecimal
    })
    void databaseRejectsAHashThatIsNotLowercaseHexSha256(String badHash) {
        var insert = nativeInsert(newFamily(), badHash, NOW, NOW.plus(TTL));

        assertThatThrownBy(insert::executeUpdate)
                .isInstanceOf(PersistenceException.class)
                .rootCause().hasMessageContaining("ck_refresh_tokens_token_hash_hex");
    }

    @Test
    void databaseRejectsATokenThatExpiresBeforeItIsCreated() {
        var insert = nativeInsert(newFamily(), hashOf("raw"), NOW, NOW);

        assertThatThrownBy(insert::executeUpdate)
                .isInstanceOf(PersistenceException.class)
                .rootCause().hasMessageContaining("ck_refresh_tokens_expires_after_creation");
    }

    @Test
    void databaseRejectsATokenOfAnUnknownFamily() {
        var insert = nativeInsert(UUID.randomUUID(), hashOf("raw"), NOW, NOW.plus(TTL));

        assertThatThrownBy(insert::executeUpdate)
                .isInstanceOf(PersistenceException.class)
                .rootCause().hasMessageContaining("fk_refresh_tokens_family");
    }

    /**
     * Two transactions consume the same token. The first holds the row lock until it commits; the
     * second waits, then PostgreSQL re-checks {@code used_at is null} and updates nothing. Exactly
     * one wins. Runs outside the test transaction so both really commit; the setup is inside the
     * try, so the cleanup runs even if the setup fails halfway.
     *
     * <p>PT: Duas transações consomem o mesmo token. A primeira segura o lock da linha até o commit;
     * a segunda espera, e então o PostgreSQL reavalia {@code used_at is null} e não atualiza nada.
     * Exatamente uma vence. Roda fora da transação do teste para que as duas realmente façam commit;
     * a preparação fica dentro do try, então a limpeza roda mesmo se a preparação falhar no meio.
     */
    @Test
    @Transactional(propagation = Propagation.NOT_SUPPORTED)
    void concurrentMarkUsedLetsExactlyOneTransactionWin() throws Exception {
        var tx = new TransactionTemplate(transactionManager);
        var email = uniqueEmail();
        ExecutorService threads = Executors.newFixedThreadPool(2);
        try {
            var family = tx.execute(status -> newFamily(email));
            var tokenId = tx.execute(status -> tokens.save(
                    RefreshToken.issue(family, hashOf("race"), NOW, NOW.plus(TTL))).getId());

            var firstUpdated = new CountDownLatch(1);
            var release = new CountDownLatch(1);
            var first = threads.submit(() -> tx.execute(status -> {
                var rows = tokens.markUsed(tokenId, NOW.plusSeconds(1));
                firstUpdated.countDown();
                await(release); // keep the row lock until the second transaction waits for it
                // PT: segura o lock da linha até a segunda transação esperar por ele
                return rows;
            }));
            assertThat(firstUpdated.await(10, TimeUnit.SECONDS)).isTrue();
            var second = threads.submit(() -> tx.execute(status -> tokens.markUsed(tokenId, NOW.plusSeconds(2))));
            LockWaits.awaitOneBlockedTransaction(tx, jpa);
            release.countDown();

            assertThat(first.get(10, TimeUnit.SECONDS)).isEqualTo(1);
            assertThat(second.get(10, TimeUnit.SECONDS)).isZero();
            assertThat(tokens.findById(tokenId).orElseThrow().getUsedAt()).isEqualTo(NOW.plusSeconds(1));
        } finally {
            threads.shutdownNow();
            // Deleting the user cascades to its families and their tokens.
            // PT: Apagar o usuário propaga em cascata para as famílias dele e os tokens delas.
            tx.executeWithoutResult(status -> users.findByEmail(email).ifPresent(users::delete));
        }
    }

    private UUID newFamily() {
        return newFamily(uniqueEmail());
    }

    private UUID newFamily(String email) {
        var user = users.save(User.register("Ana", email, TestPasswordHashes.BCRYPT, "BRL", NOW)).getId();
        return families.save(RefreshTokenFamily.start(user, NOW)).getId();
    }

    private static String uniqueEmail() {
        return "user-" + UUID.randomUUID() + "@example.com";
    }

    private Query nativeInsert(UUID familyId, String hash, Instant createdAt, Instant expiresAt) {
        entityManager.flush();
        return entityManager.getEntityManager().createNativeQuery("""
                insert into refresh_tokens (id, family_id, token_hash, expires_at, created_at)
                values (?1, ?2, ?3, ?4, ?5)
                """)
                .setParameter(1, UUID.randomUUID())
                .setParameter(2, familyId)
                .setParameter(3, hash)
                .setParameter(4, expiresAt)
                .setParameter(5, createdAt);
    }

    static String hashOf(String raw) {
        try {
            var digest = MessageDigest.getInstance("SHA-256").digest(raw.getBytes(StandardCharsets.UTF_8));
            return HexFormat.of().formatHex(digest);
        } catch (NoSuchAlgorithmException e) {
            throw new IllegalStateException(e);
        }
    }

    static void await(CountDownLatch latch) {
        try {
            if (!latch.await(10, TimeUnit.SECONDS)) {
                throw new IllegalStateException("latch not released in time");
            }
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            throw new IllegalStateException(e);
        }
    }
}
