package com.yulehohenfeld.snapledger.user.repository;

import java.util.Optional;
import java.util.UUID;

import jakarta.persistence.LockModeType;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.Query;

import com.yulehohenfeld.snapledger.user.entity.User;

/** Accounts; email uniqueness comes from uk_users_email, never an exists-query. PT: A unicidade vem da constraint.
 *  Notes: docs/code-notes/user.md#userrepository */
public interface UserRepository extends JpaRepository<User, UUID> {

    /** Login lookup; {@code email} must already be normalized ({@link User#normalizeEmail}).
     *  PT: Busca do login; o {@code email} já precisa estar normalizado ({@link User#normalizeEmail}). */
    Optional<User> findByEmail(String email);

    /** Id only, so no entity is left in the persistence context before {@link #lockById} loads the fresh row.
     *  PT: Só o id, para nenhuma entidade ficar no contexto de persistência antes de o {@link #lockById} carregar a linha atual. */
    @Query("select u.id from User u where u.email = :email")
    Optional<UUID> findIdByEmail(String email);

    /** Locks the row for the transaction; serializes password reset and email verification of one user.
     *  PT: Trava a linha na transação; serializa a redefinição de senha e a verificação de email de um usuário.
     *  Notes: docs/code-notes/user.md#lockbyid */
    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("select u from User u where u.id = :id")
    Optional<User> lockById(UUID id);
}
