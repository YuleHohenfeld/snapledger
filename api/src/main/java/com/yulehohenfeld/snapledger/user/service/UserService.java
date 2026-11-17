package com.yulehohenfeld.snapledger.user.service;

import java.time.Clock;
import java.util.Optional;
import java.util.UUID;

import lombok.RequiredArgsConstructor;

import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import com.yulehohenfeld.snapledger.shared.error.ConstraintViolations;
import com.yulehohenfeld.snapledger.shared.error.EmailAlreadyRegisteredException;
import com.yulehohenfeld.snapledger.shared.error.UnauthorizedException;
import com.yulehohenfeld.snapledger.user.dto.UserCredentials;
import com.yulehohenfeld.snapledger.user.dto.UserResponse;
import com.yulehohenfeld.snapledger.user.entity.User;
import com.yulehohenfeld.snapledger.user.mapper.UserMapper;
import com.yulehohenfeld.snapledger.user.repository.UserRepository;

/**
 * Accounts; other features reach users only through this class.
 *
 * <p>PT: Contas; outras features chegam aos usuários só por esta classe.
 * Notes: docs/code-notes/user.md#userservice
 */
@Service
@RequiredArgsConstructor
public class UserService {

    static final String EMAIL_CONSTRAINT = "uk_users_email";

    private final UserRepository users;
    private final UserMapper mapper;
    private final Clock clock;

    /**
     * Inserts the account now, inside the caller's transaction; a taken email throws
     * EmailAlreadyRegisteredException. {@code passwordHash} must already be a bcrypt hash.
     *
     * <p>PT: Insere a conta agora, dentro da transação de quem chama; um email já usado lança
     * EmailAlreadyRegisteredException. O {@code passwordHash} já precisa ser um hash bcrypt.
     * Notes: docs/code-notes/user.md#create
     */
    @Transactional
    public UserResponse create(String name, String email, String passwordHash, String currency) {
        var user = User.register(name, email, passwordHash, currency, clock.instant());
        try {
            users.saveAndFlush(user);
        } catch (DataIntegrityViolationException e) {
            if (ConstraintViolations.violates(e, EMAIL_CONSTRAINT)) {
                throw new EmailAlreadyRegisteredException();
            }
            throw e;
        }
        return mapper.toResponse(user);
    }

    /**
     * Login lookup; normalizes the email itself, so callers never see the User entity.
     *
     * <p>PT: Busca do login; normaliza o email sozinho, então quem chama nunca vê a entidade User.
     * Notes: docs/code-notes/user.md#findcredentials
     */
    @Transactional(readOnly = true)
    public Optional<UserCredentials> findCredentials(String email) {
        return users.findByEmail(User.normalizeEmail(email))
                .map(user -> new UserCredentials(mapper.toResponse(user), user.getPasswordHash()));
    }

    /**
     * Credential lookup by email (normalized here); the caller must not reveal whether it found one.
     *
     * <p>PT: Busca por email (normalizado aqui); quem chama não pode revelar se achou.
     * Notes: docs/code-notes/user.md#findidbyemail
     */
    @Transactional(readOnly = true)
    public Optional<UUID> findIdByEmail(String email) {
        return users.findIdByEmail(User.normalizeEmail(email));
    }

    /**
     * Locks the user row until the caller's transaction ends and returns its current credentials, or
     * empty when the user is gone. Serializes password reset, email verification and the login's
     * session start for one user.
     *
     * <p>PT: Trava a linha do usuário até o fim da transação de quem chama e devolve as credenciais
     * atuais, ou vazio se o usuário não existe mais. Serializa a redefinição de senha, a verificação
     * de email e o início de sessão do login de um usuário.
     * Notes: docs/code-notes/user.md#lockforupdate
     */
    @Transactional
    public Optional<UserCredentials> lockForUpdate(UUID userId) {
        return users.lockById(userId)
                .map(user -> new UserCredentials(mapper.toResponse(user), user.getPasswordHash()));
    }

    /**
     * Replaces the hash of a user already locked by the caller; {@code passwordHash} must be a bcrypt hash.
     *
     * <p>PT: Troca o hash de um usuário já travado por quem chama; o {@code passwordHash} precisa ser um hash bcrypt.
     * Notes: docs/code-notes/user.md#lockforupdate
     */
    @Transactional
    public void changePassword(UUID userId, String passwordHash) {
        users.findById(userId).ifPresent(user -> user.changePassword(passwordHash));
    }

    /**
     * Records that the user proved access to the email; keeps the first instant.
     *
     * <p>PT: Registra que o usuário provou acesso ao email; mantém o primeiro instante.
     * Notes: docs/code-notes/user.md#lockforupdate
     */
    @Transactional
    public void markEmailVerified(UUID userId) {
        users.findById(userId).ifPresent(user -> user.markEmailVerified(clock.instant()));
    }

    /**
     * The token's user; a user that no longer exists is 401 unauthorized (contract).
     *
     * <p>PT: O usuário do token; um usuário que não existe mais é 401 unauthorized (contrato).
     * Notes: docs/code-notes/user.md#getcurrent
     */
    @Transactional(readOnly = true)
    public UserResponse getCurrent(UUID userId) {
        return users.findById(userId)
                .map(mapper::toResponse)
                .orElseThrow(UnauthorizedException::new);
    }
}
