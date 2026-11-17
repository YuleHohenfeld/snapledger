package com.yulehohenfeld.snapledger.auth.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatCode;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.inOrder;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.time.ZoneOffset;
import java.util.Optional;
import java.util.UUID;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.SimpleTransactionStatus;

import com.yulehohenfeld.snapledger.accountcode.config.AccountCodeProperties;
import com.yulehohenfeld.snapledger.accountcode.entity.CodePurpose;
import com.yulehohenfeld.snapledger.accountcode.service.AccountCodeService;
import com.yulehohenfeld.snapledger.accountcode.service.AccountCodeHasher;
import com.yulehohenfeld.snapledger.accountcode.service.AccountEmails;
import com.yulehohenfeld.snapledger.auth.entity.PasswordResetGrant;
import com.yulehohenfeld.snapledger.auth.repository.PasswordResetGrantRepository;
import com.yulehohenfeld.snapledger.shared.email.MailDispatcher;
import com.yulehohenfeld.snapledger.shared.error.InvalidCodeException;
import com.yulehohenfeld.snapledger.shared.error.InvalidResetTokenException;
import com.yulehohenfeld.snapledger.shared.ratelimit.FixedWindowRateLimiter;
import com.yulehohenfeld.snapledger.shared.ratelimit.RateLimitProperties;
import com.yulehohenfeld.snapledger.support.FakeEmailSender;
import com.yulehohenfeld.snapledger.support.PasswordResetGrantFixtures;
import com.yulehohenfeld.snapledger.support.TestJwtSecret;
import com.yulehohenfeld.snapledger.user.dto.UserCredentials;
import com.yulehohenfeld.snapledger.user.dto.UserResponse;
import com.yulehohenfeld.snapledger.user.service.UserService;

/**
 * Reset rules with every collaborator mocked except the mail path (a fake sender) and the limiter.
 * What matters here: nothing differs for an unknown email, a wrong code is thrown only after the
 * transaction committed, verify issues a hashed one-use token, and confirm does all its steps together.
 *
 * <p>PT: Regras da redefinição com todos os colaboradores simulados, menos o caminho do email (um
 * sender falso) e o limitador. O que importa aqui: nada muda para um email desconhecido, um código
 * errado só é lançado depois do commit da transação, e um sucesso faz as quatro coisas juntas.
 * Notes: docs/code-notes/auth.md#passwordresetservice
 */
@ExtendWith(MockitoExtension.class)
class PasswordResetServiceTest {

    static final String EMAIL = "ana@example.com";
    static final String CODE = "042917";
    static final String NEW_PASSWORD = "pw-" + UUID.randomUUID();
    static final String NEW_HASH = "new-hash";
    static final String TOKEN = "raw-reset-token";
    static final Instant NOW = Instant.parse("2026-11-17T12:00:00Z");

    @Mock
    UserService users;

    @Mock
    AccountCodeService codes;

    @Mock
    RefreshTokenService refreshTokens;

    @Mock
    PasswordEncoder passwordEncoder;

    @Mock
    PlatformTransactionManager transactionManager;

    @Mock
    AccountCodeHasher hasher;

    @Mock
    PasswordResetGrantRepository grants;

    final FakeEmailSender sender = new FakeEmailSender();
    final UUID userId = UUID.randomUUID();
    final UserResponse ana = new UserResponse(userId, "Ana", EMAIL, "BRL", Instant.parse("2026-11-13T10:00:00Z"), false);
    final SimpleTransactionStatus transaction = new SimpleTransactionStatus();
    final Clock clock = Clock.fixed(NOW, ZoneOffset.UTC);
    PasswordResetService service;

    @BeforeEach
    void setUp() {
        var codeProps = new AccountCodeProperties(TestJwtSecret.generate(), Duration.ofMinutes(15), 5,
                Duration.ofSeconds(60), 5, 10, Duration.ofHours(24));
        var limiter = new FixedWindowRateLimiter(clock,
                new RateLimitProperties(10, 20, 20, 2, 2, Duration.ofHours(1), 100));
        service = new PasswordResetService(users, codes, new AccountEmails(codeProps),
                new MailDispatcher(sender, Runnable::run), refreshTokens, passwordEncoder, limiter,
                hasher, grants, clock, transactionManager);
    }

    // --- request ---
    // PT: --- pedido do código ---

    @Test
    void aKnownEmailGetsAResetCodeByEmail() {
        when(users.findIdByEmail(EMAIL)).thenReturn(Optional.of(userId));
        when(codes.issue(userId, CodePurpose.PASSWORD_RESET)).thenReturn(Optional.of(CODE));

        service.request(EMAIL);

        assertThat(sender.lastCodeFor(EMAIL)).contains(CODE);
        assertThat(sender.sent()).singleElement().satisfies(m -> assertThat(m.subject()).contains("password reset"));
    }

    @Test
    void anUnknownEmailSendsNothingAndReturnsNormally() {
        when(users.findIdByEmail(EMAIL)).thenReturn(Optional.empty());

        assertThatCode(() -> service.request(EMAIL)).doesNotThrowAnyException();

        verifyNoInteractions(codes);
        assertThat(sender.sent()).isEmpty();
    }

    @Test
    void aRefusedCodeIsSilent() {
        when(users.findIdByEmail(EMAIL)).thenReturn(Optional.of(userId));
        when(codes.issue(userId, CodePurpose.PASSWORD_RESET)).thenReturn(Optional.empty());

        assertThatCode(() -> service.request(EMAIL)).doesNotThrowAnyException();

        assertThat(sender.sent()).isEmpty();
    }

    // The per-email limit answers like everything else: normally, with no email and no lookup.
    // PT: O limite por email responde como todo o resto: normalmente, sem email e sem consulta.
    @Test
    void thePerEmailLimitIsSilentAndSkipsTheLookup() {
        when(users.findIdByEmail(EMAIL)).thenReturn(Optional.of(userId));
        when(codes.issue(userId, CodePurpose.PASSWORD_RESET)).thenReturn(Optional.of(CODE));
        service.request(EMAIL);
        service.request(EMAIL.toUpperCase());
        sender.clear();

        assertThatCode(() -> service.request(EMAIL)).doesNotThrowAnyException();

        assertThat(sender.sent()).isEmpty();
        verify(users, org.mockito.Mockito.times(2)).findIdByEmail(anyString());
    }

    @Test
    void aMailFailureNeverReachesTheCaller() {
        var failing = new PasswordResetService(users, codes,
                new AccountEmails(new AccountCodeProperties(TestJwtSecret.generate(), Duration.ofMinutes(15), 5,
                        Duration.ofSeconds(60), 5, 10, Duration.ofHours(24))),
                new MailDispatcher(message -> {
                    throw new IllegalStateException("smtp down");
                }, Runnable::run), refreshTokens, passwordEncoder,
                new FixedWindowRateLimiter(Clock.systemUTC(),
                        new RateLimitProperties(10, 20, 20, 5, 5, Duration.ofHours(1), 100)),
                hasher, grants, clock, transactionManager);
        when(users.findIdByEmail(EMAIL)).thenReturn(Optional.of(userId));
        when(codes.issue(userId, CodePurpose.PASSWORD_RESET)).thenReturn(Optional.of(CODE));

        assertThatCode(() -> failing.request(EMAIL)).doesNotThrowAnyException();
    }

    // --- verify ---
    // PT: --- verify (conferência do código) ---

    @Test
    void aRightCodeConsumesTheCodeAndIssuesAHashedGrantInOneTransaction() {
        stubKnownUserForVerify();
        when(codes.consume(userId, CodePurpose.PASSWORD_RESET, CODE)).thenReturn(true);

        var token = service.verify(EMAIL, CODE);

        assertThat(token.ttl()).isEqualTo(Duration.ofMinutes(10));
        // 32 random bytes in base64url without padding: 43 characters of the URL-safe alphabet.
        // PT: 32 bytes aleatórios em base64url sem padding: 43 caracteres do alfabeto seguro para URL.
        assertThat(token.value()).matches("^[A-Za-z0-9_-]{43}$");
        var hash = org.mockito.ArgumentCaptor.forClass(String.class);
        var order = inOrder(users, codes, grants, transactionManager);
        order.verify(users).lockForUpdate(userId);
        order.verify(codes).consume(userId, CodePurpose.PASSWORD_RESET, CODE);
        order.verify(grants).upsert(any(), eq(userId), hash.capture(), eq(NOW.plus(Duration.ofMinutes(10))), eq(NOW));
        order.verify(transactionManager).commit(transaction);
        // Only the SHA-256 is stored, never the token itself.
        // PT: Só o SHA-256 é gravado, nunca o token.
        assertThat(hash.getValue()).isEqualTo(RefreshTokenService.sha256(token.value()))
                .matches("^[0-9a-f]{64}$").isNotEqualTo(token.value());
        assertThat(sender.sent()).isEmpty();
    }

    @Test
    void twoVerifiesIssueDifferentTokensAndEachUpsertsTheSameUsersRow() {
        stubKnownUserForVerify();
        when(codes.consume(userId, CodePurpose.PASSWORD_RESET, CODE)).thenReturn(true);

        var first = service.verify(EMAIL, CODE);
        var second = service.verify(EMAIL, CODE);

        assertThat(first.value()).isNotEqualTo(second.value());
        // The upsert is what replaces the previous grant: one row per user.
        // PT: O upsert é o que substitui a permissão anterior: uma linha por usuário.
        verify(grants, times(2)).upsert(any(), eq(userId), anyString(), any(), any());
    }

    @Test
    void aWrongCodeThrowsInvalidCodeOnlyAfterTheTransactionCommittedAndIssuesNothing() {
        stubKnownUserForVerify();
        when(codes.consume(userId, CodePurpose.PASSWORD_RESET, CODE)).thenReturn(false);

        assertThatThrownBy(() -> service.verify(EMAIL, CODE)).isInstanceOf(InvalidCodeException.class);

        // Commit, never rollback: a rollback would undo the attempt that consume counted.
        // PT: Commit, nunca rollback: um rollback desfaria a tentativa que o consume contou.
        verify(transactionManager).commit(transaction);
        verify(transactionManager, never()).rollback(any());
        verifyNoInteractions(grants, refreshTokens);
    }

    @Test
    void anUnknownEmailPaysForAnHmacAndAnswersInvalidCode() {
        when(users.findIdByEmail(EMAIL)).thenReturn(Optional.empty());

        assertThatThrownBy(() -> service.verify(EMAIL, CODE)).isInstanceOf(InvalidCodeException.class);

        verify(hasher).hash(eq(CodePurpose.PASSWORD_RESET), any(UUID.class), eq(CODE));
        verifyNoInteractions(codes, grants);
    }

    @Test
    void aUserDeletedBetweenLookupAndLockIsInvalidCodeToo() {
        stubKnownUserForVerify();
        when(users.lockForUpdate(userId)).thenReturn(Optional.empty());

        assertThatThrownBy(() -> service.verify(EMAIL, CODE)).isInstanceOf(InvalidCodeException.class);

        verifyNoInteractions(codes, grants);
    }

    // Same answer as an unknown email: the per-email limit must not tell which emails exist.
    // PT: Mesma resposta de um email desconhecido: o limite por email não pode dizer quais emails existem.
    @Test
    void thePerEmailVerifyLimitAnswersInvalidCodeWithoutTouchingTheDatabase() {
        stubKnownUserForVerify();
        when(codes.consume(userId, CodePurpose.PASSWORD_RESET, CODE)).thenReturn(false);
        for (int i = 0; i < 2; i++) {
            assertThatThrownBy(() -> service.verify(EMAIL, CODE)).isInstanceOf(InvalidCodeException.class);
        }

        assertThatThrownBy(() -> service.verify(EMAIL, CODE)).isInstanceOf(InvalidCodeException.class);

        verify(codes, times(2)).consume(any(), any(), anyString());
        verify(users, times(2)).findIdByEmail(anyString());
    }

    // --- confirm ---
    // PT: --- confirmação ---

    @Test
    void aValidTokenChangesTheHashMarksVerifiedRevokesEverySessionSpendsTheGrantAndSendsTheChangedEmail() {
        var grant = stubLiveGrant(NOW.plusSeconds(300), null);

        service.confirm(TOKEN, NEW_PASSWORD);

        var order = inOrder(passwordEncoder, users, grants, refreshTokens, transactionManager);
        order.verify(passwordEncoder).encode(NEW_PASSWORD);
        // Lock order: user, then grant, then the sessions.
        // PT: Ordem de locks: usuário, depois permissão, depois as sessões.
        order.verify(users).lockForUpdate(userId);
        order.verify(grants).lockByTokenHash(RefreshTokenService.sha256(TOKEN));
        order.verify(users).changePassword(userId, NEW_HASH);
        order.verify(users).markEmailVerified(userId);
        order.verify(refreshTokens).revokeAllOf(userId);
        order.verify(transactionManager).commit(transaction);
        assertThat(grant.getUsedAt()).isEqualTo(NOW);
        assertThat(sender.sent()).singleElement().satisfies(m -> {
            assertThat(m.to()).isEqualTo(EMAIL);
            assertThat(m.subject()).contains("password was changed");
        });
    }

    @Test
    void theRawPasswordNeverReachesTheUserService() {
        stubLiveGrant(NOW.plusSeconds(300), null);

        service.confirm(TOKEN, NEW_PASSWORD);

        verify(users, never()).changePassword(any(), eq(NEW_PASSWORD));
    }

    @Test
    void anUnknownTokenStillHashesFirstAndAnswersInvalidResetToken() {
        when(passwordEncoder.encode(NEW_PASSWORD)).thenReturn(NEW_HASH);
        when(grants.findUserIdByTokenHash(RefreshTokenService.sha256(TOKEN))).thenReturn(Optional.empty());

        assertThatThrownBy(() -> service.confirm(TOKEN, NEW_PASSWORD)).isInstanceOf(InvalidResetTokenException.class);

        verifyNoInteractions(users, refreshTokens);
        assertThat(sender.sent()).isEmpty();
    }

    @Test
    void anExpiredTokenChangesNothing() {
        stubLiveGrant(NOW, null);

        assertThatThrownBy(() -> service.confirm(TOKEN, NEW_PASSWORD)).isInstanceOf(InvalidResetTokenException.class);

        verifyNothingChanged();
    }

    @Test
    void aUsedTokenChangesNothing() {
        stubLiveGrant(NOW.plusSeconds(300), NOW.minusSeconds(5));

        assertThatThrownBy(() -> service.confirm(TOKEN, NEW_PASSWORD)).isInstanceOf(InvalidResetTokenException.class);

        verifyNothingChanged();
    }

    // A new verify replaced the grant between the unlocked lookup and the lock: the old hash finds nothing.
    // PT: Um verify novo substituiu a permissão entre a busca sem lock e o lock: o hash antigo não acha nada.
    @Test
    void aGrantReplacedBetweenLookupAndLockIsInvalidResetToken() {
        stubLookup();
        when(grants.lockByTokenHash(RefreshTokenService.sha256(TOKEN))).thenReturn(Optional.empty());

        assertThatThrownBy(() -> service.confirm(TOKEN, NEW_PASSWORD)).isInstanceOf(InvalidResetTokenException.class);

        verifyNothingChanged();
    }

    @Test
    void aUserDeletedBetweenLookupAndLockIsInvalidResetTokenToo() {
        when(transactionManager.getTransaction(any())).thenReturn(transaction);
        when(grants.findUserIdByTokenHash(RefreshTokenService.sha256(TOKEN))).thenReturn(Optional.of(userId));
        when(users.lockForUpdate(userId)).thenReturn(Optional.empty());

        assertThatThrownBy(() -> service.confirm(TOKEN, NEW_PASSWORD)).isInstanceOf(InvalidResetTokenException.class);

        verify(grants, never()).lockByTokenHash(anyString());
        verifyNoInteractions(refreshTokens);
    }

    private void verifyNothingChanged() {
        verify(users, never()).changePassword(any(), any());
        verify(users, never()).markEmailVerified(any());
        verify(refreshTokens, never()).revokeAllOf(any());
        assertThat(sender.sent()).isEmpty();
    }

    private void stubKnownUserForVerify() {
        when(transactionManager.getTransaction(any())).thenReturn(transaction);
        when(users.findIdByEmail(EMAIL)).thenReturn(Optional.of(userId));
        org.mockito.Mockito.lenient().when(users.lockForUpdate(userId))
                .thenReturn(Optional.of(new UserCredentials(ana, "old-hash")));
    }

    private void stubLookup() {
        when(passwordEncoder.encode(NEW_PASSWORD)).thenReturn(NEW_HASH);
        when(transactionManager.getTransaction(any())).thenReturn(transaction);
        when(grants.findUserIdByTokenHash(RefreshTokenService.sha256(TOKEN))).thenReturn(Optional.of(userId));
        when(users.lockForUpdate(userId)).thenReturn(Optional.of(new UserCredentials(ana, "old-hash")));
    }

    private PasswordResetGrant stubLiveGrant(Instant expiresAt, Instant usedAt) {
        stubLookup();
        var grant = PasswordResetGrantFixtures.row(userId, RefreshTokenService.sha256(TOKEN), NOW.minusSeconds(600), expiresAt, usedAt);
        when(grants.lockByTokenHash(RefreshTokenService.sha256(TOKEN))).thenReturn(Optional.of(grant));
        return grant;
    }
}
