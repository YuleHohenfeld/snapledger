package com.yulehohenfeld.snapledger.auth.service;

import static com.yulehohenfeld.snapledger.support.LockWaits.await;
import static com.yulehohenfeld.snapledger.support.TestTokenHashes.hashOf;
import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatCode;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.assertj.core.api.Assertions.catchThrowable;

import java.sql.Timestamp;
import java.time.Duration;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;
import java.util.concurrent.Callable;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutionException;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;

import jakarta.persistence.EntityManager;

import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.context.annotation.Import;
import org.springframework.dao.CannotAcquireLockException;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.support.TransactionTemplate;

import com.yulehohenfeld.snapledger.auth.entity.RefreshToken;
import com.yulehohenfeld.snapledger.auth.repository.RefreshTokenFamilyRepository;
import com.yulehohenfeld.snapledger.auth.repository.RefreshTokenRepository;
import com.yulehohenfeld.snapledger.shared.error.ApiException;
import com.yulehohenfeld.snapledger.shared.error.InvalidRefreshTokenException;
import com.yulehohenfeld.snapledger.support.LockWaits;
import com.yulehohenfeld.snapledger.support.RefreshTokenFixtures;
import com.yulehohenfeld.snapledger.support.TestJwtSecret;
import com.yulehohenfeld.snapledger.support.TestPasswordHashes;
import com.yulehohenfeld.snapledger.support.TestcontainersConfiguration;
import com.yulehohenfeld.snapledger.user.entity.User;
import com.yulehohenfeld.snapledger.user.repository.UserRepository;

/**
 * rotate and revokeFamilyOf through the real transactional proxy on a real PostgreSQL, with real
 * commits and concurrent transactions (ADR 0002, ADR 0008 and its amendment).
 *
 * <p>PT: rotate e revokeFamilyOf pelo proxy transacional real num PostgreSQL real, com commits reais
 * e transações concorrentes (ADR 0002, ADR 0008 e a emenda dele).
 * Notes: docs/code-notes/auth.md#rotate
 */
@SpringBootTest
// MockMvc is unused here: kept so the cached context (and container) is shared with
// AuthIntegrationTest and AuthSessionIntegrationTest.
// PT: O MockMvc não é usado aqui: mantido para que o contexto em cache (e o container) seja
//     compartilhado com AuthIntegrationTest e AuthSessionIntegrationTest.
@AutoConfigureMockMvc
@Import({TestcontainersConfiguration.class, TestJwtSecret.class})
@Transactional(propagation = Propagation.NOT_SUPPORTED)
class RefreshTokenServiceIntegrationTest {

    static final Duration TTL = Duration.ofDays(30);

    @Autowired
    RefreshTokenService service;

    @Autowired
    RefreshTokenRepository tokens;

    @Autowired
    RefreshTokenFamilyRepository families;

    @Autowired
    UserRepository users;

    @Autowired
    JdbcTemplate jdbc;

    // The shared, transaction-bound EntityManager; usable from any thread inside a TransactionTemplate.
    // PT: O EntityManager compartilhado, ligado à transação; usável de qualquer thread dentro de um TransactionTemplate.
    @Autowired
    EntityManager jpa;

    @Autowired
    PlatformTransactionManager transactionManager;

    TransactionTemplate tx;
    ExecutorService threads;
    RefreshTokenFixtures fixtures;

    @BeforeEach
    void setUp() {
        tx = new TransactionTemplate(transactionManager);
        threads = Executors.newFixedThreadPool(2);
        fixtures = new RefreshTokenFixtures(jdbc);
    }

    @AfterEach
    void cleanUp() {
        fixtures.cleanUp(threads);
    }

    // The test ADR 0008 requires: the revocation survives the 401 (noRollbackFor), so the newest token dies too.
    // PT: O teste que o ADR 0008 exige: a revogação sobrevive ao 401 (noRollbackFor), então o token mais
    //     novo morre também.
    @Test
    void reuseRevokesTheFamilyAndTheNewestTokenFails() {
        var first = service.startFamily(newUser());
        var family = fixtures.familyOf(first.value());
        var second = service.rotate(first.value()).refreshToken();

        assertThatThrownBy(() -> service.rotate(first.value())).isInstanceOf(InvalidRefreshTokenException.class);

        assertThat(fixtures.revokedAt(family)).isNotNull();
        assertThatThrownBy(() -> service.rotate(second.value())).isInstanceOf(InvalidRefreshTokenException.class);
        assertThat(tokenCount(family)).isEqualTo(2);
    }

    @Test
    void rotationConsumesTheOldTokenAndIssuesTheNextInTheSameFamily() {
        var userId = newUser();
        var first = service.startFamily(userId);
        var family = fixtures.familyOf(first.value());

        var rotation = service.rotate(first.value());

        assertThat(rotation.userId()).isEqualTo(userId);
        assertThat(fixtures.familyOf(rotation.refreshToken().value())).isEqualTo(family);
        assertThat(usedAt(first.value())).isNotNull();
        assertThat(usedAt(rotation.refreshToken().value())).isNull();
        assertThat(service.rotate(rotation.refreshToken().value()).userId()).isEqualTo(userId);
    }

    @Test
    void reuseInOneSessionLeavesAnotherSessionOfTheSameUserAlive() {
        var userId = newUser();
        var stolen = service.startFamily(userId);
        var otherDevice = service.startFamily(userId);
        service.rotate(stolen.value());

        catchThrowable(() -> service.rotate(stolen.value()));

        assertThat(fixtures.revokedAt(fixtures.familyOf(stolen.value()))).isNotNull();
        assertThat(fixtures.revokedAt(fixtures.familyOf(otherDevice.value()))).isNull();
        assertThat(service.rotate(otherDevice.value()).userId()).isEqualTo(userId);
    }

    // Expired is not reuse: 401, the session stays active and another live token of it still rotates.
    // PT: Vencido não é reuso: 401, a sessão continua ativa e outro token vivo dela ainda rotaciona.
    @Test
    void anExpiredTokenIs401AndLeavesItsSessionAlive() {
        var live = service.startFamily(newUser());
        var family = fixtures.familyOf(live.value());
        var expired = fixtures.insertExpiredToken(family);

        assertThatThrownBy(() -> service.rotate(expired)).isInstanceOf(InvalidRefreshTokenException.class);

        assertThat(fixtures.revokedAt(family)).isNull();
        assertThat(usedAt(expired)).isNull();
        assertThat(service.rotate(live.value()).refreshToken().value()).isNotBlank();
    }

    @Test
    void anUnknownTokenIs401() {
        assertThatThrownBy(() -> service.rotate("unknown-" + UUID.randomUUID()))
                .isExactlyInstanceOf(InvalidRefreshTokenException.class);
    }

    @Test
    void aTokenOfARevokedFamilyIs401AndIsNotConsumed() {
        var token = service.startFamily(newUser());
        service.revokeFamilyOf(token.value());

        assertThatThrownBy(() -> service.rotate(token.value())).isInstanceOf(InvalidRefreshTokenException.class);
        assertThat(usedAt(token.value())).isNull();
    }

    // Two rotations of the same token: the family lock serializes them, the second sees "used" = reuse.
    // PT: Duas rotações do mesmo token: o lock da família as serializa, a segunda vê "usado" = reuso.
    @Test
    void twoConcurrentRotationsOfTheSameTokenGiveExactlyOneSuccessAndKillTheSession() throws Exception {
        var token = service.startFamily(newUser());
        var family = fixtures.familyOf(token.value());
        var start = new CountDownLatch(1);
        Callable<RefreshTokenService.Rotation> rotate = () -> {
            await(start);
            return service.rotate(token.value());
        };
        var first = threads.submit(rotate);
        var second = threads.submit(rotate);
        start.countDown();

        var outcomes = new ArrayList<Object>();
        for (var future : List.of(first, second)) {
            try {
                outcomes.add(future.get(10, TimeUnit.SECONDS));
            } catch (ExecutionException e) {
                outcomes.add(e.getCause());
            }
        }

        assertThat(outcomes).filteredOn(RefreshTokenService.Rotation.class::isInstance).hasSize(1);
        assertThat(outcomes).filteredOn(InvalidRefreshTokenException.class::isInstance).hasSize(1);
        assertThat(fixtures.revokedAt(family)).isNotNull();
        var winner = outcomes.stream().filter(RefreshTokenService.Rotation.class::isInstance)
                .map(RefreshTokenService.Rotation.class::cast).findFirst().orElseThrow();
        assertThatThrownBy(() -> service.rotate(winner.refreshToken().value()))
                .isInstanceOf(InvalidRefreshTokenException.class);
    }

    // Revocation first: the rotation waits on the family row, then finds it revoked and issues nothing.
    // PT: Revogação primeiro: a rotação espera na linha da família, depois a encontra revogada e não emite nada.
    @Test
    void aRotationWaitingForALogoutGets401AndIssuesNoToken() throws Exception {
        var token = service.startFamily(newUser());
        var family = fixtures.familyOf(token.value());
        var revoked = new CountDownLatch(1);
        var release = new CountDownLatch(1);
        try {
            var logout = threads.submit(() -> tx.execute(status -> {
                var rows = families.revoke(family, Instant.now());
                revoked.countDown();
                await(release); // family row locked, revocation not committed yet
                // PT: linha da família travada, revogação ainda sem commit
                return rows;
            }));
            await(revoked);
            var rotation = threads.submit(() -> service.rotate(token.value()));
            LockWaits.awaitOneBlockedTransaction(tx, jpa);
            release.countDown();

            assertThat(logout.get(10, TimeUnit.SECONDS)).isEqualTo(1);
            var failure = catchThrowable(() -> rotation.get(10, TimeUnit.SECONDS));
            assertThat(failure).isInstanceOf(ExecutionException.class)
                    .cause().isInstanceOf(InvalidRefreshTokenException.class);
            assertThat(tokenCount(family)).isEqualTo(1);
            assertThat(usedAt(token.value())).isNull();
        } finally {
            release.countDown();
        }
    }

    // Rotation first: the logout waits for it, and the token that rotation issued is dead afterwards.
    // PT: Rotação primeiro: o logout espera por ela, e o token que essa rotação emitiu está morto depois.
    @Test
    void aLogoutWaitingForARotationKillsTheTokenThatRotationIssued() throws Exception {
        var token = service.startFamily(newUser());
        var family = fixtures.familyOf(token.value());
        var next = "next-" + UUID.randomUUID();
        var inserted = new CountDownLatch(1);
        var release = new CountDownLatch(1);
        try {
            var rotation = threads.submit(() -> tx.execute(status -> {
                families.lockActive(family).orElseThrow();
                var now = Instant.now();
                var current = tokens.findByTokenHash(hashOf(token.value())).orElseThrow();
                assertThat(tokens.markUsed(current.getId(), now)).isEqualTo(1);
                tokens.saveAndFlush(RefreshToken.issue(family, hashOf(next), now, now.plus(TTL)));
                inserted.countDown();
                await(release); // Tn+1 inserted, not committed
                // PT: Tn+1 inserido, sem commit
                return null;
            }));
            await(inserted);
            var logout = threads.submit(() -> service.revokeFamilyOf(token.value()));
            LockWaits.awaitOneBlockedTransaction(tx, jpa);
            release.countDown();

            rotation.get(10, TimeUnit.SECONDS);
            logout.get(10, TimeUnit.SECONDS);
            assertThat(fixtures.revokedAt(family)).isNotNull();
            assertThatThrownBy(() -> service.rotate(next)).isInstanceOf(InvalidRefreshTokenException.class);
        } finally {
            release.countDown();
        }
    }

    @Test
    void revokeFamilyOfAnUnknownTokenDoesNothing() {
        assertThatCode(() -> service.revokeFamilyOf("unknown-" + UUID.randomUUID())).doesNotThrowAnyException();
    }

    // Owner decision Q2: an already used token still ends its session on logout.
    // PT: Decisão Q2: um token já usado ainda encerra a sessão dele no logout.
    @Test
    void revokeFamilyOfAUsedTokenEndsTheSession() {
        var first = service.startFamily(newUser());
        var second = service.rotate(first.value()).refreshToken();

        service.revokeFamilyOf(first.value());

        assertThat(fixtures.revokedAt(fixtures.familyOf(first.value()))).isNotNull();
        assertThatThrownBy(() -> service.rotate(second.value())).isInstanceOf(InvalidRefreshTokenException.class);
    }

    @Test
    void revokeFamilyOfAnExpiredTokenEndsTheSession() {
        var live = service.startFamily(newUser());
        var family = fixtures.familyOf(live.value());
        var expired = fixtures.insertExpiredToken(family);

        service.revokeFamilyOf(expired);
        service.revokeFamilyOf(expired);

        assertThat(fixtures.revokedAt(family)).isNotNull();
        assertThatThrownBy(() -> service.rotate(live.value())).isInstanceOf(InvalidRefreshTokenException.class);
    }

    // ADR 0009: a lock wait past lock_timeout is a database error (masked 500), never a 401, and the
    // token is untouched, so the client can simply retry.
    // PT: ADR 0009: uma espera de lock além do lock_timeout é um erro de banco (500 mascarado), nunca
    //     401, e o token fica intacto, então o cliente pode simplesmente tentar de novo.
    @Test
    void aLockTimeoutPropagatesAndLeavesTheTokenUsable() throws Exception {
        var token = service.startFamily(newUser());
        var family = fixtures.familyOf(token.value());
        var locked = new CountDownLatch(1);
        var release = new CountDownLatch(1);
        try {
            var holder = threads.submit(() -> tx.execute(status -> {
                families.lockActive(family).orElseThrow();
                locked.countDown();
                await(release);
                return null;
            }));
            await(locked);

            var failure = catchThrowable(() -> service.rotate(token.value()));
            release.countDown();
            holder.get(10, TimeUnit.SECONDS);

            assertThat(failure).isInstanceOf(CannotAcquireLockException.class).isNotInstanceOf(ApiException.class);
            assertThat(usedAt(token.value())).isNull();
            assertThat(fixtures.revokedAt(family)).isNull();
            assertThat(service.rotate(token.value()).refreshToken().value()).isNotBlank();
        } finally {
            release.countDown();
        }
    }

    private UUID newUser() {
        var email = fixtures.uniqueEmail();
        return tx.execute(status -> users.save(
                User.register("Ana", email, TestPasswordHashes.BCRYPT, "BRL", Instant.now())).getId());
    }

    private Timestamp usedAt(String raw) {
        return jdbc.queryForObject("select used_at from refresh_tokens where token_hash = ?", Timestamp.class, hashOf(raw));
    }

    private int tokenCount(UUID family) {
        return jdbc.queryForObject("select count(*) from refresh_tokens where family_id = ?", Integer.class, family);
    }
}
