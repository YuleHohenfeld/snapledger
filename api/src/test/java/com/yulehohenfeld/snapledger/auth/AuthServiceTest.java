package com.yulehohenfeld.snapledger.auth;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.assertj.core.api.Assertions.catchThrowable;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.inOrder;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
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
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.support.SimpleTransactionStatus;

import com.yulehohenfeld.snapledger.auth.dto.LoginRequest;
import com.yulehohenfeld.snapledger.auth.dto.RegisterRequest;
import com.yulehohenfeld.snapledger.auth.dto.TokenResponse;
import com.yulehohenfeld.snapledger.shared.error.EmailAlreadyRegisteredException;
import com.yulehohenfeld.snapledger.shared.error.InvalidCredentialsException;
import com.yulehohenfeld.snapledger.user.UserCredentials;
import com.yulehohenfeld.snapledger.user.UserService;
import com.yulehohenfeld.snapledger.user.dto.UserResponse;

/**
 * Register and login rules with every collaborator mocked. Real atomicity (rollback) is proven by
 * AuthIntegrationTest; here only the order of calls and the shape of failures.
 *
 * <p>PT: Regras de cadastro e login com todos os colaboradores simulados. A atomicidade real
 * (rollback) é provada pelo AuthIntegrationTest; aqui só a ordem das chamadas e o formato das falhas.
 */
@ExtendWith(MockitoExtension.class)
class AuthServiceTest {

    static final String DUMMY_HASH = "dummy-hash";
    static final String STORED_HASH = "stored-hash";
    static final String NEW_HASH = "new-hash";
    static final String PASSWORD = UUID.randomUUID().toString();
    static final Duration ACCESS_TTL = Duration.ofMinutes(15);
    static final Duration REFRESH_TTL = Duration.ofDays(30);

    @Mock
    UserService users;

    @Mock
    AccessTokenService accessTokens;

    @Mock
    RefreshTokenService refreshTokens;

    @Mock
    PasswordEncoder passwordEncoder;

    @Mock
    PlatformTransactionManager transactionManager;

    AuthService service;

    final UserResponse ana = new UserResponse(UUID.randomUUID(), "Ana", "ana@example.com", "BRL",
            Instant.parse("2026-11-13T10:00:00Z"));

    @BeforeEach
    void setUp() {
        when(passwordEncoder.encode(anyString())).thenReturn(DUMMY_HASH);
        service = new AuthService(users, accessTokens, refreshTokens, passwordEncoder, transactionManager);
    }

    @Test
    void theDummyHashIsComputedOnceAtStartupWithTheSameEncoder() {
        verify(passwordEncoder, times(1)).encode(anyString());
    }

    // Hash, then one transaction around create + session, then commit (ADR 0009).
    // PT: Hash, depois uma transação em volta de create + sessão, depois commit (ADR 0009).
    @Test
    void registerHashesBeforeOpeningTheTransactionThatCreatesAccountAndSession() {
        var transaction = new SimpleTransactionStatus();
        when(transactionManager.getTransaction(any())).thenReturn(transaction);
        when(passwordEncoder.encode(PASSWORD)).thenReturn(NEW_HASH);
        when(users.create("Ana", "ana@example.com", NEW_HASH, "BRL")).thenReturn(ana);
        stubSession(ana.id());

        var response = service.register(new RegisterRequest("Ana", "ana@example.com", PASSWORD, null));

        var order = inOrder(passwordEncoder, transactionManager, users, refreshTokens, accessTokens);
        order.verify(passwordEncoder).encode(PASSWORD);
        order.verify(transactionManager).getTransaction(any());
        order.verify(users).create("Ana", "ana@example.com", NEW_HASH, "BRL");
        order.verify(refreshTokens).startFamily(ana.id());
        order.verify(accessTokens).issue(ana.id());
        order.verify(transactionManager).commit(transaction);
        assertThat(response.user()).isSameAs(ana);
        assertTokens(response.tokens());
    }

    @Test
    void registerNeverPassesTheRawPasswordToTheUserService() {
        when(passwordEncoder.encode(PASSWORD)).thenReturn(NEW_HASH);
        when(users.create(any(), any(), any(), any())).thenReturn(ana);
        stubSession(ana.id());

        service.register(new RegisterRequest("Ana", "ana@example.com", PASSWORD, "BRL"));

        verify(users, never()).create(any(), any(), eq(PASSWORD), any());
    }

    @Test
    void registerWithATakenEmailStartsNoSessionAndRollsBack() {
        var transaction = new SimpleTransactionStatus();
        when(transactionManager.getTransaction(any())).thenReturn(transaction);
        when(passwordEncoder.encode(PASSWORD)).thenReturn(NEW_HASH);
        when(users.create(any(), any(), any(), any())).thenThrow(new EmailAlreadyRegisteredException());

        assertThatThrownBy(() -> service.register(new RegisterRequest("Ana", "ana@example.com", PASSWORD, "BRL")))
                .isInstanceOf(EmailAlreadyRegisteredException.class);
        verify(refreshTokens, never()).startFamily(any());
        verify(accessTokens, never()).issue(any());
        verify(transactionManager).rollback(transaction);
        verify(transactionManager, never()).commit(any());
    }

    // An annotation would open the transaction (and take a connection) before bcrypt runs.
    // PT: Uma anotação abriria a transação (e pegaria uma conexão) antes de o bcrypt rodar.
    @Test
    void neitherRegisterNorLoginIsAnnotatedTransactional() throws Exception {
        assertThat(AuthService.class.getMethod("register", RegisterRequest.class)
                .getAnnotation(Transactional.class)).isNull();
        assertThat(AuthService.class.getMethod("login", LoginRequest.class)
                .getAnnotation(Transactional.class)).isNull();
        assertThat(AuthService.class.getAnnotation(Transactional.class)).isNull();
    }

    @Test
    void loginWithTheRightPasswordStartsASession() {
        when(users.findCredentials("ana@example.com")).thenReturn(Optional.of(new UserCredentials(ana, STORED_HASH)));
        when(passwordEncoder.matches(PASSWORD, STORED_HASH)).thenReturn(true);
        stubSession(ana.id());

        var response = service.login(new LoginRequest("ana@example.com", PASSWORD));

        assertThat(response.user()).isSameAs(ana);
        assertTokens(response.tokens());
    }

    // Unknown email still runs bcrypt, against the dummy hash, so it takes about as long.
    // PT: Email desconhecido ainda roda o bcrypt, contra o hash falso, então leva mais ou menos o mesmo tempo.
    @Test
    void loginWithAnUnknownEmailChecksTheDummyHashAndFails() {
        when(users.findCredentials("nobody@example.com")).thenReturn(Optional.empty());

        assertThatThrownBy(() -> service.login(new LoginRequest("nobody@example.com", PASSWORD)))
                .isInstanceOf(InvalidCredentialsException.class);
        verify(passwordEncoder).matches(PASSWORD, DUMMY_HASH);
        verify(refreshTokens, never()).startFamily(any());
        verify(accessTokens, never()).issue(any());
    }

    // Even if the dummy hash matched by accident, an unknown email never logs in.
    // PT: Mesmo se o hash falso batesse por acaso, um email desconhecido nunca entra.
    @Test
    void loginWithAnUnknownEmailFailsEvenIfTheDummyHashMatched() {
        when(users.findCredentials("nobody@example.com")).thenReturn(Optional.empty());
        when(passwordEncoder.matches(PASSWORD, DUMMY_HASH)).thenReturn(true);

        assertThatThrownBy(() -> service.login(new LoginRequest("nobody@example.com", PASSWORD)))
                .isInstanceOf(InvalidCredentialsException.class);
        verify(refreshTokens, never()).startFamily(any());
    }

    @Test
    void unknownEmailAndWrongPasswordFailTheSameWay() {
        when(users.findCredentials("nobody@example.com")).thenReturn(Optional.empty());
        when(users.findCredentials("ana@example.com")).thenReturn(Optional.of(new UserCredentials(ana, STORED_HASH)));
        when(passwordEncoder.matches(PASSWORD, STORED_HASH)).thenReturn(false);
        when(passwordEncoder.matches(PASSWORD, DUMMY_HASH)).thenReturn(false);

        var unknown = catchThrowable(() -> service.login(new LoginRequest("nobody@example.com", PASSWORD)));
        var wrong = catchThrowable(() -> service.login(new LoginRequest("ana@example.com", PASSWORD)));

        assertThat(unknown).isInstanceOf(InvalidCredentialsException.class);
        assertThat(wrong).isExactlyInstanceOf(unknown.getClass()).hasMessage(unknown.getMessage());
        verify(passwordEncoder).matches(PASSWORD, STORED_HASH);
        verify(refreshTokens, never()).startFamily(any());
    }

    private void stubSession(UUID userId) {
        when(refreshTokens.startFamily(userId)).thenReturn(new IssuedToken("refresh-value", REFRESH_TTL));
        when(accessTokens.issue(userId)).thenReturn(new IssuedToken("access-value", ACCESS_TTL));
    }

    private static void assertTokens(TokenResponse tokens) {
        assertThat(tokens.accessToken()).isEqualTo("access-value");
        assertThat(tokens.tokenType()).isEqualTo("Bearer");
        assertThat(tokens.expiresIn()).isEqualTo(900);
        assertThat(tokens.refreshToken()).isEqualTo("refresh-value");
        assertThat(tokens.refreshExpiresIn()).isEqualTo(2_592_000);
    }
}
