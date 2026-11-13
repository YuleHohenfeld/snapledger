package com.yulehohenfeld.snapledger.user;

import java.util.Optional;
import java.util.UUID;

import org.springframework.data.jpa.repository.JpaRepository;

/** Accounts; email uniqueness comes from uk_users_email, never an exists-query. PT: A unicidade vem da constraint.
 *  Notes: docs/code-notes/user.md#userrepository */
public interface UserRepository extends JpaRepository<User, UUID> {

    /** Login lookup; {@code email} must already be normalized ({@link User#normalizeEmail}).
     *  PT: Busca do login; o {@code email} já precisa estar normalizado ({@link User#normalizeEmail}). */
    Optional<User> findByEmail(String email);
}
