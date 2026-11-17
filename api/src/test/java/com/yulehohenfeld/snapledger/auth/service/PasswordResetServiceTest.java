package com.yulehohenfeld.snapledger.auth.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatCode;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
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
import com.yulehohenfeld.snapledger.accountcode.service.AccountEmails;
import com.yulehohenfeld.snapledger.shared.email.MailDispatcher;
import com.yulehohenfeld.snapledger.shared.error.InvalidCodeException;
import com.yulehohenfeld.snapledger.shared.ratelimit.FixedWindowRateLimiter;
import com.yulehohenfeld.snapledger.shared.ratelimit.RateLimitProperties;
import com.yulehohenfeld.snapledger.support.FakeEmailSender;
import com.yulehohenfeld.snapledger.support.TestJwtSecret;
import com.yulehohenfeld.snapledger.user.dto.UserCredentials;
import com.yulehohenfeld.snapledger.user.dto.UserResponse;
import com.yulehohenfeld.snapledger.user.service.UserService;

/**
 * Reset rules with every collaborator mocked except the mail path (a fake sender) and the limiter.
 * What matters here: nothing differs for an unknown email, a wrong code is thrown only after the
 * transaction committed, and a success does all four things together.
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

    final FakeEmailSender sender = new FakeEmailSender();
    final UUID userId = UUID.randomUUID();
    final UserResponse ana = new UserResponse(userId, "Ana", EMAIL, "BRL", Instant.parse("2026-11-13T10:00:00Z"), false);
    final SimpleTransactionStatus transaction = new SimpleTransactionStatus();
    PasswordResetService service;

    @BeforeEach
    void setUp() {
        var codeProps = new AccountCodeProperties(TestJwtSecret.generate(), Duration.ofMinutes(15), 5,
                Duration.ofSeconds(60), 5, 10, Duration.ofHours(24));
        var limiter = new FixedWindowRateLimiter(Clock.fixed(Instant.parse("2026-11-17T12:00:00Z"), ZoneOffset.UTC),
                new RateLimitProperties(10, 20, 2, 2, Duration.ofHours(1), 100));
        service = new PasswordResetService(users, codes, new AccountEmails(codeProps),
                new MailDispatcher(sender, Runnable::run), refreshTokens, passwordEncoder, limiter,
                transactionManager);
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
                        new RateLimitProperties(10, 20, 5, 5, Duration.ofHours(1), 100)),
                transactionManager);
        when(users.findIdByEmail(EMAIL)).thenReturn(Optional.of(userId));
        when(codes.issue(userId, CodePurpose.PASSWORD_RESET)).thenReturn(Optional.of(CODE));

        assertThatCode(() -> failing.request(EMAIL)).doesNotThrowAnyException();
    }

    // --- confirm ---
    // PT: --- confirmação ---

    @Test
    void aWrongCodeThrowsInvalidCodeOnlyAfterTheTransactionCommitted() {
        stubKnownUser();
        when(codes.consume(userId, CodePurpose.PASSWORD_RESET, CODE)).thenReturn(false);

        assertThatThrownBy(() -> service.confirm(EMAIL, CODE, NEW_PASSWORD)).isInstanceOf(InvalidCodeException.class);

        // Commit, never rollback: a rollback would undo the attempt that consume counted.
        // PT: Commit, nunca rollback: um rollback desfaria a tentativa que o consume contou.
        verify(transactionManager).commit(transaction);
        verify(transactionManager, never()).rollback(any());
        verify(users, never()).changePassword(any(), any());
        verify(refreshTokens, never()).revokeAllOf(any());
        assertThat(sender.sent()).isEmpty();
    }

    @Test
    void anUnknownEmailStillHashesFirstAndAnswersInvalidCode() {
        when(passwordEncoder.encode(NEW_PASSWORD)).thenReturn(NEW_HASH);
        when(transactionManager.getTransaction(any())).thenReturn(transaction);
        when(users.findIdByEmail(EMAIL)).thenReturn(Optional.empty());

        assertThatThrownBy(() -> service.confirm(EMAIL, CODE, NEW_PASSWORD)).isInstanceOf(InvalidCodeException.class);

        var order = inOrder(passwordEncoder, transactionManager);
        order.verify(passwordEncoder).encode(NEW_PASSWORD);
        order.verify(transactionManager).getTransaction(any());
        verifyNoInteractions(codes, refreshTokens);
    }

    @Test
    void aUserDeletedBetweenLookupAndLockIsInvalidCodeToo() {
        when(passwordEncoder.encode(NEW_PASSWORD)).thenReturn(NEW_HASH);
        when(transactionManager.getTransaction(any())).thenReturn(transaction);
        when(users.findIdByEmail(EMAIL)).thenReturn(Optional.of(userId));
        when(users.lockForUpdate(userId)).thenReturn(Optional.empty());

        assertThatThrownBy(() -> service.confirm(EMAIL, CODE, NEW_PASSWORD)).isInstanceOf(InvalidCodeException.class);

        verifyNoInteractions(codes);
    }

    @Test
    void aSuccessChangesTheHashMarksVerifiedRevokesEverySessionAndSendsTheChangedEmail() {
        stubKnownUser();
        when(codes.consume(userId, CodePurpose.PASSWORD_RESET, CODE)).thenReturn(true);

        service.confirm(EMAIL, CODE, NEW_PASSWORD);

        var order = inOrder(passwordEncoder, users, codes, refreshTokens, transactionManager);
        order.verify(passwordEncoder).encode(NEW_PASSWORD);
        order.verify(users).lockForUpdate(userId);
        order.verify(codes).consume(userId, CodePurpose.PASSWORD_RESET, CODE);
        order.verify(users).changePassword(userId, NEW_HASH);
        order.verify(users).markEmailVerified(userId);
        order.verify(refreshTokens).revokeAllOf(userId);
        order.verify(transactionManager).commit(transaction);
        assertThat(sender.sent()).singleElement().satisfies(m -> {
            assertThat(m.to()).isEqualTo(EMAIL);
            assertThat(m.subject()).contains("password was changed");
        });
    }

    @Test
    void theRawPasswordNeverReachesTheUserService() {
        stubKnownUser();
        when(codes.consume(userId, CodePurpose.PASSWORD_RESET, CODE)).thenReturn(true);

        service.confirm(EMAIL, CODE, NEW_PASSWORD);

        verify(users, never()).changePassword(any(), org.mockito.ArgumentMatchers.eq(NEW_PASSWORD));
    }

    // Same answer as an unknown email: the per-email limit must not tell which emails exist.
    // PT: Mesma resposta de um email desconhecido: o limite por email não pode dizer quais emails existem.
    @Test
    void thePerEmailConfirmLimitAnswersInvalidCodeWithoutTouchingTheDatabase() {
        stubKnownUser();
        when(codes.consume(userId, CodePurpose.PASSWORD_RESET, CODE)).thenReturn(false);
        for (int i = 0; i < 2; i++) {
            assertThatThrownBy(() -> service.confirm(EMAIL, CODE, NEW_PASSWORD)).isInstanceOf(InvalidCodeException.class);
        }

        assertThatThrownBy(() -> service.confirm(EMAIL, CODE, NEW_PASSWORD)).isInstanceOf(InvalidCodeException.class);

        verify(codes, org.mockito.Mockito.times(2)).consume(any(), any(), anyString());
        verify(passwordEncoder, org.mockito.Mockito.times(3)).encode(NEW_PASSWORD);
    }

    private void stubKnownUser() {
        when(passwordEncoder.encode(NEW_PASSWORD)).thenReturn(NEW_HASH);
        when(transactionManager.getTransaction(any())).thenReturn(transaction);
        when(users.findIdByEmail(EMAIL)).thenReturn(Optional.of(userId));
        when(users.lockForUpdate(userId)).thenReturn(Optional.of(new UserCredentials(ana, "old-hash")));
    }
}
