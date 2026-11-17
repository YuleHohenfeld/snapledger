package com.yulehohenfeld.snapledger.auth.service;

import java.util.UUID;

import lombok.extern.slf4j.Slf4j;

import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;

import com.yulehohenfeld.snapledger.auth.dto.AuthResponse;
import com.yulehohenfeld.snapledger.auth.dto.LoginRequest;
import com.yulehohenfeld.snapledger.auth.dto.RefreshRequest;
import com.yulehohenfeld.snapledger.auth.dto.RegisterRequest;
import com.yulehohenfeld.snapledger.auth.dto.TokenResponse;
import com.yulehohenfeld.snapledger.shared.error.InvalidCredentialsException;
import com.yulehohenfeld.snapledger.user.dto.UserCredentials;
import com.yulehohenfeld.snapledger.user.dto.UserResponse;
import com.yulehohenfeld.snapledger.user.service.EmailVerificationService;
import com.yulehohenfeld.snapledger.user.service.UserService;

/**
 * Register, login, refresh and logout: start, renew and end a session.
 *
 * <p>PT: Cadastro, login, refresh e logout: iniciam, renovam e encerram uma sessão.
 * Notes: docs/code-notes/auth.md#authservice
 */
@Slf4j
@Service
public class AuthService {

    private final UserService users;
    private final EmailVerificationService emailVerification;
    private final AccessTokenService accessTokens;
    private final RefreshTokenService refreshTokens;
    private final PasswordEncoder passwordEncoder;

    // Own instance, not the shared bean: TransactionTemplate is mutable, so its settings stay here.
    // PT: Instância própria, não o bean compartilhado: o TransactionTemplate é mutável, então as
    //     configurações dele ficam aqui.
    private final TransactionTemplate transaction;

    // Same encoder, so same cost as a real hash; the password behind it is thrown away.
    // PT: Mesmo encoder, então o mesmo custo de um hash real; a senha por trás dele é descartada.
    private final String dummyHash;

    public AuthService(UserService users, EmailVerificationService emailVerification,
                       AccessTokenService accessTokens,
                       RefreshTokenService refreshTokens, PasswordEncoder passwordEncoder,
                       PlatformTransactionManager transactionManager) {
        this.users = users;
        this.emailVerification = emailVerification;
        this.accessTokens = accessTokens;
        this.refreshTokens = refreshTokens;
        this.passwordEncoder = passwordEncoder;
        this.transaction = new TransactionTemplate(transactionManager);
        this.dummyHash = passwordEncoder.encode(UUID.randomUUID().toString());
    }

    /**
     * Atomic (contract): the account and its session are created together, or nothing is. Hashes
     * first, so no pool connection is held during bcrypt (ADR 0009).
     *
     * <p>PT: Atômico (contrato): a conta e a sessão dela são criadas juntas, ou nada é criado. Gera
     * o hash antes, então nenhuma conexão do pool fica presa durante o bcrypt (ADR 0009).
     * Notes: docs/code-notes/auth.md#register
     */
    public AuthResponse register(RegisterRequest request) {
        var passwordHash = passwordEncoder.encode(request.password());
        var response = transaction.execute(status -> startSession(
                users.create(request.name(), request.email(), passwordHash, request.currency())));
        sendVerificationCode(response.user().id());
        return response;
    }

    /**
     * Unknown email and wrong password fail the same way, in similar time. No outer transaction.
     *
     * <p>PT: Email desconhecido e senha errada falham do mesmo jeito, em tempo parecido. Sem
     * transação externa.
     * Notes: docs/code-notes/auth.md#login
     */
    public AuthResponse login(LoginRequest request) {
        var account = users.findCredentials(request.email());
        var hash = account.map(UserCredentials::passwordHash).orElse(dummyHash);
        var matches = passwordEncoder.matches(request.password(), hash);
        if (account.isEmpty() || !matches) {
            throw new InvalidCredentialsException();
        }
        var user = account.get().user();
        return transaction.execute(status -> startSessionIfUnchanged(user, hash));
    }

    /**
     * Rotates the refresh token, then signs an access token for the session's owner.
     *
     * <p>PT: Rotaciona o refresh token e depois assina um token de acesso para o dono da sessão.
     * Notes: docs/code-notes/auth.md#refresh
     */
    // Never transactional: an outer transaction would roll back the reuse revocation of rotate.
    // PT: Nunca transacional: uma transação externa desfaria a revogação por reuso do rotate.
    public TokenResponse refresh(RefreshRequest request) {
        var rotation = refreshTokens.rotate(request.refreshToken());
        var access = accessTokens.issue(rotation.userId());
        var refresh = rotation.refreshToken();
        return TokenResponse.bearer(access.value(), access.ttl(), refresh.value(), refresh.ttl());
    }

    /**
     * Ends the session of the token; idempotent and silent about unknown tokens (contract).
     *
     * <p>PT: Encerra a sessão do token; idempotente e calado sobre tokens desconhecidos (contrato).
     * Notes: docs/code-notes/auth.md#logout
     */
    public void logout(RefreshRequest request) {
        refreshTokens.revokeFamilyOf(request.refreshToken());
    }

    // Locks the user row and re-reads the hash: a password reset that committed after matches() read
    // the old hash must not be followed by a session created with the old password.
    // PT: Trava a linha do usuário e relê o hash: uma redefinição de senha confirmada depois de o
    //     matches() ler o hash antigo não pode ser seguida de uma sessão criada com a senha antiga.
    // Notes: docs/code-notes/auth.md#login-race
    private AuthResponse startSessionIfUnchanged(UserResponse user, String verifiedHash) {
        var current = users.lockForUpdate(user.id()).orElseThrow(InvalidCredentialsException::new);
        if (!current.passwordHash().equals(verifiedHash)) {
            throw new InvalidCredentialsException();
        }
        return startSession(user);
    }

    // Best effort: a throttled or failed code never fails the registration that already committed.
    // PT: Melhor esforço: um código limitado ou que falhou nunca faz falhar o cadastro já confirmado.
    private void sendVerificationCode(UUID userId) {
        try {
            emailVerification.send(userId);
        } catch (RuntimeException e) {
            log.warn("Verification code not sent after register: {}", e.getClass().getName());
        }
    }

    private AuthResponse startSession(UserResponse user) {
        var refresh = refreshTokens.startFamily(user.id());
        var access = accessTokens.issue(user.id());
        return new AuthResponse(user,
                TokenResponse.bearer(access.value(), access.ttl(), refresh.value(), refresh.ttl()));
    }
}
