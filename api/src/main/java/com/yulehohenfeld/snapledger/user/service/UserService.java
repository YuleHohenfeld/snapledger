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
