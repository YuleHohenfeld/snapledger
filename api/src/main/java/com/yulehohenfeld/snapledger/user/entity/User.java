package com.yulehohenfeld.snapledger.user.entity;

import java.time.Instant;
import java.util.Locale;
import java.util.UUID;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Table;

import lombok.AccessLevel;
import lombok.Getter;
import lombok.NoArgsConstructor;

import com.yulehohenfeld.snapledger.shared.persistence.AssignedIdEntity;

/** An account, built only through {@link #register}. PT: Uma conta, criada só pelo {@link #register}.
 *  Notes: docs/code-notes/user.md#user */
@Entity
@Table(name = "users")
@Getter
@NoArgsConstructor(access = AccessLevel.PROTECTED) // JPA only
// PT: só para o JPA
public class User extends AssignedIdEntity {

    @Column(nullable = false, length = 80)
    private String name;

    @Column(nullable = false, length = 254, updatable = false)
    private String email;

    @Column(name = "password_hash", nullable = false, length = 72)
    private String passwordHash;

    @Column(nullable = false, length = 3)
    private String currency;

    @Column(name = "created_at", nullable = false, updatable = false)
    private Instant createdAt;

    private User(UUID id) {
        super(id);
    }

    /** A new account; the caller has already validated the request and hashed the password.
     *  PT: Uma conta nova; quem chama já validou a requisição e gerou o hash da senha. */
    public static User register(String name, String email, String passwordHash, String currency, Instant now) {
        var user = new User(UUID.randomUUID());
        user.name = name.strip();
        user.email = normalizeEmail(email);
        user.passwordHash = passwordHash;
        user.currency = currency;
        user.createdAt = now;
        return user;
    }

    /** The stored form of an email; register and login must both use it. PT: Cadastro e login precisam usar esta forma.
     *  Notes: docs/code-notes/user.md#normalizeemail */
    public static String normalizeEmail(String email) {
        return email.toLowerCase(Locale.ROOT);
    }

    // Only the id: name, email and password hash are personal or secret and must never reach a log.
    // PT: Só o id: nome, email e hash da senha são dados pessoais ou secretos e nunca podem chegar a um log.
    @Override
    public String toString() {
        return "User[id=" + getId() + "]";
    }
}
