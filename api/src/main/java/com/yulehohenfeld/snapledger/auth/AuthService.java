package com.yulehohenfeld.snapledger.auth;

import java.util.UUID;

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
import com.yulehohenfeld.snapledger.user.UserCredentials;
import com.yulehohenfeld.snapledger.user.UserService;
import com.yulehohenfeld.snapledger.user.dto.UserResponse;

/**
 * Register, login, refresh and logout: start, renew and end a session.
 *
 * <p>PT: Cadastro, login, refresh e logout: iniciam, renovam e encerram uma sessão.
 * Notes: docs/code-notes/auth.md#authservice
 */
@Service
public class AuthService {

    private final UserService users;
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

    public AuthService(UserService users, AccessTokenService accessTokens,
                       RefreshTokenService refreshTokens, PasswordEncoder passwordEncoder,
                       PlatformTransactionManager transactionManager) {
        this.users = users;
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
        return transaction.execute(status -> startSession(
                users.create(request.name(), request.email(), passwordHash, request.currency())));
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
        return startSession(account.get().user());
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

    private AuthResponse startSession(UserResponse user) {
        var refresh = refreshTokens.startFamily(user.id());
        var access = accessTokens.issue(user.id());
        return new AuthResponse(user,
                TokenResponse.bearer(access.value(), access.ttl(), refresh.value(), refresh.ttl()));
    }
}
