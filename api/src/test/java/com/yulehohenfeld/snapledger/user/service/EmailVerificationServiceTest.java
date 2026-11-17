package com.yulehohenfeld.snapledger.user.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

import java.time.Duration;
import java.time.Instant;
import java.util.Optional;
import java.util.UUID;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.SimpleTransactionStatus;

import com.yulehohenfeld.snapledger.accountcode.config.AccountCodeProperties;
import com.yulehohenfeld.snapledger.accountcode.entity.CodePurpose;
import com.yulehohenfeld.snapledger.accountcode.service.AccountCodeService;
import com.yulehohenfeld.snapledger.accountcode.service.AccountEmails;
import com.yulehohenfeld.snapledger.shared.email.MailDispatcher;
import com.yulehohenfeld.snapledger.shared.error.InvalidCodeException;
import com.yulehohenfeld.snapledger.shared.error.TooManyRequestsException;
import com.yulehohenfeld.snapledger.shared.error.UnauthorizedException;
import com.yulehohenfeld.snapledger.support.FakeEmailSender;
import com.yulehohenfeld.snapledger.support.TestJwtSecret;
import com.yulehohenfeld.snapledger.user.dto.UserCredentials;
import com.yulehohenfeld.snapledger.user.dto.UserResponse;

/**
 * Verification rules with the collaborators mocked: who gets an email, when the answer is "wait",
 * and that a wrong code is thrown only after the transaction committed.
 *
 * <p>PT: Regras da verificação com os colaboradores simulados: quem recebe email, quando a resposta
 * é "espere", e que um código errado só é lançado depois do commit da transação.
 * Notes: docs/code-notes/user.md#emailverificationservice
 */
@ExtendWith(MockitoExtension.class)
class EmailVerificationServiceTest {

    static final String CODE = "042917";

    @Mock
    UserService users;

    @Mock
    AccountCodeService codes;

    @Mock
    PlatformTransactionManager transactionManager;

    final FakeEmailSender sender = new FakeEmailSender();
    final UUID userId = UUID.randomUUID();
    final SimpleTransactionStatus transaction = new SimpleTransactionStatus();
    EmailVerificationService service;

    @BeforeEach
    void setUp() {
        var props = new AccountCodeProperties(TestJwtSecret.generate(), Duration.ofMinutes(15), 5,
                Duration.ofSeconds(60), 5, 10, Duration.ofHours(24));
        service = new EmailVerificationService(users, codes, new AccountEmails(props),
                new MailDispatcher(sender, Runnable::run), transactionManager);
    }

    @Test
    void sendEmailsTheCodeToTheAccountAddress() {
        when(users.getCurrent(userId)).thenReturn(user(false));
        when(codes.issue(userId, CodePurpose.EMAIL_VERIFICATION)).thenReturn(Optional.of(CODE));

        service.send(userId);

        assertThat(sender.lastCodeFor("ana@example.com")).contains(CODE);
    }

    @Test
    void anAlreadyVerifiedAccountSendsNothingAndIssuesNothing() {
        when(users.getCurrent(userId)).thenReturn(user(true));

        service.send(userId);

        verifyNoInteractions(codes);
        assertThat(sender.sent()).isEmpty();
    }

    @Test
    void aRefusedCodeIsTooManyRequestsWithTheResendCooldownAsWait() {
        when(users.getCurrent(userId)).thenReturn(user(false));
        when(codes.issue(userId, CodePurpose.EMAIL_VERIFICATION)).thenReturn(Optional.empty());
        when(codes.resendCooldown()).thenReturn(Duration.ofSeconds(60));

        assertThatThrownBy(() -> service.send(userId))
                .isInstanceOfSatisfying(TooManyRequestsException.class,
                        e -> assertThat(e.retryAfterSeconds()).isEqualTo(60));
        assertThat(sender.sent()).isEmpty();
    }

    @Test
    void sendForAUserThatIsGoneIsUnauthorized() {
        when(users.getCurrent(userId)).thenThrow(new UnauthorizedException());

        assertThatThrownBy(() -> service.send(userId)).isInstanceOf(UnauthorizedException.class);
    }

    @Test
    void confirmWithTheRightCodeMarksVerifiedAndReturnsTheProfile() {
        stubLock(false);
        when(codes.consume(userId, CodePurpose.EMAIL_VERIFICATION, CODE)).thenReturn(true);
        when(users.getCurrent(userId)).thenReturn(user(true));

        var response = service.confirm(userId, CODE);

        verify(users).markEmailVerified(userId);
        verify(transactionManager).commit(transaction);
        assertThat(response.emailVerified()).isTrue();
    }

    @Test
    void aWrongCodeThrowsInvalidCodeOnlyAfterTheTransactionCommitted() {
        stubLock(false);
        when(codes.consume(userId, CodePurpose.EMAIL_VERIFICATION, CODE)).thenReturn(false);

        assertThatThrownBy(() -> service.confirm(userId, CODE)).isInstanceOf(InvalidCodeException.class);

        verify(transactionManager).commit(transaction);
        verify(transactionManager, never()).rollback(any());
        verify(users, never()).markEmailVerified(any());
    }

    @Test
    void confirmOnAnAlreadyVerifiedAccountReturnsTheProfileAndLeavesTheCodeAlone() {
        stubLock(true);
        when(users.getCurrent(userId)).thenReturn(user(true));

        var response = service.confirm(userId, CODE);

        verifyNoInteractions(codes);
        verify(users, never()).markEmailVerified(any());
        assertThat(response.emailVerified()).isTrue();
    }

    @Test
    void confirmForAUserThatIsGoneIsUnauthorized() {
        when(transactionManager.getTransaction(any())).thenReturn(transaction);
        when(users.lockForUpdate(userId)).thenReturn(Optional.empty());

        assertThatThrownBy(() -> service.confirm(userId, CODE)).isInstanceOf(UnauthorizedException.class);
    }

    private void stubLock(boolean verified) {
        when(transactionManager.getTransaction(any())).thenReturn(transaction);
        when(users.lockForUpdate(userId)).thenReturn(Optional.of(new UserCredentials(user(verified), "hash")));
    }

    private UserResponse user(boolean verified) {
        return new UserResponse(userId, "Ana", "ana@example.com", "BRL", Instant.parse("2026-11-13T10:00:00Z"), verified);
    }
}
