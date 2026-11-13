package com.yulehohenfeld.snapledger.auth;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.assertj.core.api.Assertions.catchThrowable;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.inOrder;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.time.ZoneOffset;
import java.util.Base64;
import java.util.Optional;
import java.util.UUID;

import ch.qos.logback.classic.Level;
import ch.qos.logback.classic.Logger;
import ch.qos.logback.classic.spi.ILoggingEvent;
import ch.qos.logback.core.read.ListAppender;

import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.slf4j.LoggerFactory;
import org.springframework.dao.CannotAcquireLockException;
import org.springframework.transaction.annotation.Transactional;

import com.yulehohenfeld.snapledger.shared.error.InvalidRefreshTokenException;

/**
 * Generating, rotating and revoking refresh tokens: entropy, encoding, what is stored, and the
 * order rotate must follow (ADR 0008). Repositories mocked; real locks are in
 * RefreshTokenServiceIntegrationTest.
 *
 * <p>PT: Gerar, rotacionar e revogar refresh tokens: entropia, codificação, o que é gravado, e a
 * ordem que o rotate precisa seguir (ADR 0008). Repositórios simulados; os locks reais estão no
 * RefreshTokenServiceIntegrationTest.
 */
@ExtendWith(MockitoExtension.class)
class RefreshTokenServiceTest {

    static final Instant NOW = Instant.parse("2026-11-13T10:00:00Z");
    static final Duration TTL = Duration.ofDays(30);
    static final String RAW = "raw-" + UUID.randomUUID();

    @Mock
    RefreshTokenRepository tokens;

    @Mock
    RefreshTokenFamilyRepository families;

    ArgumentCaptor<RefreshTokenFamily> savedFamily = ArgumentCaptor.forClass(RefreshTokenFamily.class);
    ArgumentCaptor<RefreshToken> savedToken = ArgumentCaptor.forClass(RefreshToken.class);

    RefreshTokenService service;

    final UUID userId = UUID.randomUUID();
    final RefreshTokenFamily family = RefreshTokenFamily.start(userId, NOW.minus(Duration.ofDays(1)));

    Logger serviceLogger;
    ListAppender<ILoggingEvent> logLines;

    @BeforeEach
    void setUp() {
        service = new RefreshTokenService(tokens, families, new RefreshTokenProperties(TTL),
                Clock.fixed(NOW, ZoneOffset.UTC));
        serviceLogger = (Logger) LoggerFactory.getLogger(RefreshTokenService.class);
        logLines = new ListAppender<>();
        logLines.start();
        serviceLogger.addAppender(logLines);
    }

    @AfterEach
    void detachLogCapture() {
        serviceLogger.detachAppender(logLines);
    }

    @Test
    void startFamilyCreatesTheFamilyThenItsFirstToken() {
        var owner = UUID.randomUUID();

        var issued = startFamily(owner);

        var createdFamily = savedFamily.getValue();
        var firstToken = savedToken.getValue();
        assertThat(createdFamily.getUserId()).isEqualTo(owner);
        assertThat(createdFamily.getCreatedAt()).isEqualTo(NOW);
        assertThat(firstToken.getFamilyId()).isEqualTo(createdFamily.getId());
        assertThat(firstToken.getCreatedAt()).isEqualTo(NOW);
        assertThat(firstToken.getExpiresAt()).isEqualTo(NOW.plus(TTL));
        assertThat(firstToken.getUsedAt()).isNull();
        assertThat(issued.ttl()).isEqualTo(TTL);
    }

    @Test
    void theRawTokenIs256RandomBitsInBase64UrlWithoutPadding() {
        var raw = startFamily(UUID.randomUUID()).value();

        assertThat(raw).hasSize(43).matches("^[A-Za-z0-9_-]+$");
        assertThat(Base64.getUrlDecoder().decode(raw)).hasSize(RefreshTokenService.TOKEN_BYTES).hasSize(32);
    }

    @Test
    void onlyTheHexSha256IsStoredNeverTheRawToken() {
        var raw = startFamily(UUID.randomUUID()).value();

        assertThat(savedToken.getValue().getTokenHash())
                .matches("^[0-9a-f]{64}$")
                .isEqualTo(RefreshTokenService.sha256(raw))
                .isNotEqualTo(raw);
    }

    @Test
    void sha256MatchesAKnownVector() {
        // FIPS 180-2 test vector for "abc".
        // PT: Vetor de teste do FIPS 180-2 para "abc".
        assertThat(RefreshTokenService.sha256("abc"))
                .isEqualTo("ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad");
    }

    @Test
    void everyCallIssuesADifferentToken() {
        var first = startFamily(UUID.randomUUID()).value();
        var second = startFamily(UUID.randomUUID()).value();

        assertThat(first).isNotEqualTo(second);
    }

    // --- rotate ---
    // PT: --- rotate (rotação) ---

    // ADR 0008: family lock first, then consume, then insert the next token.
    // PT: ADR 0008: lock da família primeiro, depois consumir, depois inserir o próximo token.
    @Test
    void rotateLocksTheFamilyBeforeConsumingAndIssuing() {
        var current = stubActiveToken(NOW.plus(TTL));
        when(tokens.markUsed(current.getId(), NOW)).thenReturn(1);
        when(tokens.save(savedToken.capture())).thenAnswer(invocation -> invocation.getArgument(0));

        service.rotate(RAW);

        var order = inOrder(tokens, families);
        order.verify(tokens).findByTokenHash(RefreshTokenService.sha256(RAW));
        order.verify(families).lockActive(family.getId());
        order.verify(tokens).markUsed(current.getId(), NOW);
        order.verify(tokens).save(any(RefreshToken.class));
        verify(families, never()).revoke(any(), any());
    }

    @Test
    void rotateReturnsTheFamilysOwnerAndANewTokenOfTheSameFamily() {
        var current = stubActiveToken(NOW.plus(TTL));
        when(tokens.markUsed(current.getId(), NOW)).thenReturn(1);
        when(tokens.save(savedToken.capture())).thenAnswer(invocation -> invocation.getArgument(0));

        var rotation = service.rotate(RAW);

        var next = savedToken.getValue();
        assertThat(rotation.userId()).isEqualTo(userId);
        assertThat(rotation.refreshToken().ttl()).isEqualTo(TTL);
        assertThat(rotation.refreshToken().value()).isNotEqualTo(RAW).matches("^[A-Za-z0-9_-]{43}$");
        assertThat(next.getFamilyId()).isEqualTo(family.getId());
        assertThat(next.getTokenHash())
                .isEqualTo(RefreshTokenService.sha256(rotation.refreshToken().value()))
                .isNotEqualTo(current.getTokenHash());
        assertThat(next.getCreatedAt()).isEqualTo(NOW);
        assertThat(next.getExpiresAt()).isEqualTo(NOW.plus(TTL));
    }

    @Test
    void rotateOfAnUnknownTokenIs401AndLocksNothing() {
        when(tokens.findByTokenHash(RefreshTokenService.sha256(RAW))).thenReturn(Optional.empty());

        assertThatThrownBy(() -> service.rotate(RAW)).isInstanceOf(InvalidRefreshTokenException.class);
        verifyNoInteractions(families);
        verify(tokens, never()).markUsed(any(), any());
    }

    // Revoked (or revoked while we waited): 401, nothing consumed, nothing revoked again.
    // PT: Revogada (ou revogada enquanto esperávamos): 401, nada consumido, nada revogado de novo.
    @Test
    void rotateOfARevokedFamilyIs401AndConsumesNothing() {
        var current = RefreshToken.issue(family.getId(), RefreshTokenService.sha256(RAW), NOW, NOW.plus(TTL));
        when(tokens.findByTokenHash(RefreshTokenService.sha256(RAW))).thenReturn(Optional.of(current));
        when(families.lockActive(family.getId())).thenReturn(Optional.empty());

        assertThatThrownBy(() -> service.rotate(RAW)).isInstanceOf(InvalidRefreshTokenException.class);
        verify(tokens, never()).markUsed(any(), any());
        verify(families, never()).revoke(any(), any());
        verify(tokens, never()).save(any());
    }

    // Expired is not reuse: 401 and the session stays alive. The boundary (expiresAt == now) is expired.
    // PT: Vencido não é reuso: 401 e a sessão continua viva. O limite (expiresAt == now) é vencido.
    @ParameterizedTest
    @ValueSource(longs = {0, 1, 86_400})
    void rotateOfAnExpiredTokenIs401WithoutRevokingTheSession(long secondsAgo) {
        stubActiveToken(NOW.minusSeconds(secondsAgo));

        assertThatThrownBy(() -> service.rotate(RAW)).isInstanceOf(InvalidRefreshTokenException.class);
        verify(tokens, never()).markUsed(any(), any());
        verify(families, never()).revoke(any(), any());
        verify(tokens, never()).save(any());
    }

    @Test
    void rotateOfATokenValidForOneMoreMicrosecondStillRotates() {
        var current = stubActiveToken(NOW.plusNanos(1_000));
        when(tokens.markUsed(current.getId(), NOW)).thenReturn(1);
        when(tokens.save(any(RefreshToken.class))).thenAnswer(invocation -> invocation.getArgument(0));

        assertThat(service.rotate(RAW).userId()).isEqualTo(userId);
    }

    // markUsed 0 under the family lock can only mean "already used": revoke the session, then 401.
    // PT: markUsed 0 sob o lock da família só pode significar "já usado": revoga a sessão, depois 401.
    @Test
    void rotateOfAReusedTokenRevokesTheFamilyThenFails() {
        var current = stubActiveToken(NOW.plus(TTL));
        when(tokens.markUsed(current.getId(), NOW)).thenReturn(0);
        when(families.revoke(family.getId(), NOW)).thenReturn(1);

        assertThatThrownBy(() -> service.rotate(RAW)).isInstanceOf(InvalidRefreshTokenException.class);
        var order = inOrder(tokens, families);
        order.verify(families).lockActive(family.getId());
        order.verify(tokens).markUsed(current.getId(), NOW);
        order.verify(families).revoke(family.getId(), NOW);
        verify(tokens, never()).save(any());
    }

    // One WARN line with the family id only: never the token, its hash or the user (owner decision Q3).
    // PT: Uma linha WARN só com o id da família: nunca o token, o hash dele ou o usuário (decisão Q3).
    @Test
    void reuseLogsOneWarningWithOnlyTheFamilyId() {
        var current = stubActiveToken(NOW.plus(TTL));
        when(tokens.markUsed(current.getId(), NOW)).thenReturn(0);

        catchThrowable(() -> service.rotate(RAW));

        assertThat(logLines.list).singleElement().satisfies(line -> {
            assertThat(line.getLevel()).isEqualTo(Level.WARN);
            assertThat(line.getFormattedMessage())
                    .isEqualTo("Refresh token reuse detected; family revoked familyId=" + family.getId())
                    .doesNotContain(RAW)
                    .doesNotContain(RefreshTokenService.sha256(RAW))
                    .doesNotContain(userId.toString());
            assertThat(line.getThrowableProxy()).isNull();
        });
    }

    @Test
    void anUnknownTokenFailsWithAFixedCauselessException() {
        when(tokens.findByTokenHash(any())).thenReturn(Optional.empty());

        var failure = catchThrowable(() -> service.rotate(RAW));

        assertThat(failure).isExactlyInstanceOf(InvalidRefreshTokenException.class).hasNoCause();
        assertThat(failure.getMessage()).doesNotContain(RAW);
    }

    // A lock timeout is a masked 500, never a 401 that would wipe a healthy session (ADR 0009).
    // PT: Um lock timeout é um 500 mascarado, nunca um 401 que apagaria uma sessão saudável (ADR 0009).
    @Test
    void aLockTimeoutPropagatesUnchanged() {
        var current = RefreshToken.issue(family.getId(), RefreshTokenService.sha256(RAW), NOW, NOW.plus(TTL));
        var timeout = new CannotAcquireLockException("lock timeout");
        when(tokens.findByTokenHash(RefreshTokenService.sha256(RAW))).thenReturn(Optional.of(current));
        when(families.lockActive(family.getId())).thenThrow(timeout);

        assertThat(catchThrowable(() -> service.rotate(RAW))).isSameAs(timeout);
        verify(tokens, never()).markUsed(any(), any());
        verify(families, never()).revoke(any(), any());
    }

    // "now" is read after the lock: a rotation that waited must judge expiry at the time it runs.
    // PT: O "now" é lido depois do lock: uma rotação que esperou precisa julgar a validade na hora em que roda.
    @Test
    void rotateReadsTheClockAfterTheFamilyLock() {
        var clock = mock(Clock.class);
        when(clock.instant()).thenReturn(NOW);
        service = new RefreshTokenService(tokens, families, new RefreshTokenProperties(TTL), clock);
        var current = stubActiveToken(NOW.plus(TTL));
        when(tokens.markUsed(current.getId(), NOW)).thenReturn(1);
        when(tokens.save(any(RefreshToken.class))).thenAnswer(invocation -> invocation.getArgument(0));

        service.rotate(RAW);

        var order = inOrder(families, clock);
        order.verify(families).lockActive(family.getId());
        order.verify(clock).instant();
    }

    // PostgreSQL keeps microseconds; the expiry check and markUsed must compare the same instant.
    // PT: O PostgreSQL guarda microssegundos; a checagem de validade e o markUsed precisam comparar o
    //     mesmo instante.
    @Test
    void rotateTruncatesNowToMicroseconds() {
        service = new RefreshTokenService(tokens, families, new RefreshTokenProperties(TTL),
                Clock.fixed(NOW.plusNanos(1_999), ZoneOffset.UTC));
        var current = stubActiveToken(NOW.plus(TTL));
        when(tokens.markUsed(current.getId(), NOW.plusNanos(1_000))).thenReturn(1);
        when(tokens.save(any(RefreshToken.class))).thenAnswer(invocation -> invocation.getArgument(0));

        service.rotate(RAW);

        verify(tokens).markUsed(current.getId(), NOW.plusNanos(1_000));
    }

    // Expiry one microsecond after a nanosecond clock: untruncated, pgjdbc would round now up to the
    // expiry, markUsed would return 0 and a healthy session would be revoked (ADR 0008 amendment point 5).
    // PT: Validade um microssegundo depois de um relógio com nanos: sem truncar, o pgjdbc arredondaria o
    //     now para cima até a validade, o markUsed devolveria 0 e uma sessão saudável seria revogada.
    @Test
    void aNanosecondClockJustBeforeExpiryRotatesInsteadOfLookingLikeReuse() {
        service = new RefreshTokenService(tokens, families, new RefreshTokenProperties(TTL),
                Clock.fixed(NOW.plusNanos(1_999), ZoneOffset.UTC));
        var current = stubActiveToken(NOW.plusNanos(2_000));
        when(tokens.markUsed(current.getId(), NOW.plusNanos(1_000))).thenReturn(1);
        when(tokens.save(any(RefreshToken.class))).thenAnswer(invocation -> invocation.getArgument(0));

        assertThat(service.rotate(RAW).userId()).isEqualTo(userId);
        verify(families, never()).revoke(any(), any());
    }

    // Deliberate annotation guard: without noRollbackFor the reuse revocation would be rolled back with
    // the 401. The real proof is RefreshTokenServiceIntegrationTest (ADR 0008 amendment).
    // PT: Guarda deliberada da anotação: sem noRollbackFor a revogação por reuso seria desfeita junto
    //     com o 401. A prova real é o RefreshTokenServiceIntegrationTest (emenda do ADR 0008).
    @Test
    void rotateIsAWriteTransactionThatCommitsDespiteItsOwnException() throws Exception {
        var rotate = RefreshTokenService.class.getMethod("rotate", String.class).getAnnotation(Transactional.class);

        assertThat(rotate).isNotNull();
        assertThat(rotate.noRollbackFor()).containsExactly(InvalidRefreshTokenException.class);
        assertThat(rotate.readOnly()).isFalse();
    }

    // Deliberate annotation guard: logout writes the revocation.
    // PT: Guarda deliberada da anotação: o logout grava a revogação.
    @Test
    void revokeFamilyOfIsAWriteTransaction() throws Exception {
        var logout = RefreshTokenService.class.getMethod("revokeFamilyOf", String.class)
                .getAnnotation(Transactional.class);

        assertThat(logout).isNotNull();
        assertThat(logout.readOnly()).isFalse();
    }

    // --- revokeFamilyOf ---
    // PT: --- revokeFamilyOf (logout) ---

    // Owner decision Q2: any token the server knows ends its session, even an expired one.
    // PT: Decisão Q2: qualquer token que o servidor conhece encerra a sessão, mesmo um vencido.
    @ParameterizedTest
    @ValueSource(longs = {-86_400, 0, 86_400})
    void revokeFamilyOfRevokesTheSessionOfAnyKnownToken(long secondsUntilExpiry) {
        var known = RefreshToken.issue(family.getId(), RefreshTokenService.sha256(RAW),
                NOW.minus(TTL), NOW.plusSeconds(secondsUntilExpiry));
        when(tokens.findByTokenHash(RefreshTokenService.sha256(RAW))).thenReturn(Optional.of(known));

        service.revokeFamilyOf(RAW);

        verify(families).revoke(family.getId(), NOW);
        verify(families, never()).lockActive(any());
    }

    @Test
    void revokeFamilyOfAnUnknownTokenDoesNothingAndDoesNotFail() {
        when(tokens.findByTokenHash(RefreshTokenService.sha256(RAW))).thenReturn(Optional.empty());

        service.revokeFamilyOf(RAW);

        verifyNoInteractions(families);
    }

    // Already revoked (revoke returns 0) is still a silent success: logout is idempotent.
    // PT: Já revogada (revoke devolve 0) continua sendo sucesso silencioso: o logout é idempotente.
    @Test
    void revokeFamilyOfAnAlreadyRevokedSessionDoesNotFail() {
        var known = RefreshToken.issue(family.getId(), RefreshTokenService.sha256(RAW), NOW, NOW.plus(TTL));
        when(tokens.findByTokenHash(RefreshTokenService.sha256(RAW))).thenReturn(Optional.of(known));
        when(families.revoke(family.getId(), NOW)).thenReturn(0);

        service.revokeFamilyOf(RAW);

        verify(families).revoke(family.getId(), NOW);
    }

    private RefreshToken stubActiveToken(Instant expiresAt) {
        var current = RefreshToken.issue(family.getId(), RefreshTokenService.sha256(RAW),
                expiresAt.minus(TTL), expiresAt);
        when(tokens.findByTokenHash(RefreshTokenService.sha256(RAW))).thenReturn(Optional.of(current));
        when(families.lockActive(family.getId())).thenReturn(Optional.of(family));
        return current;
    }

    private IssuedToken startFamily(UUID owner) {
        when(families.save(savedFamily.capture())).thenAnswer(invocation -> invocation.getArgument(0));
        when(tokens.save(savedToken.capture())).thenAnswer(invocation -> invocation.getArgument(0));
        return service.startFamily(owner);
    }
}
