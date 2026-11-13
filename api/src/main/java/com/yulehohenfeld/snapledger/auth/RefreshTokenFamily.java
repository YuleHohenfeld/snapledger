package com.yulehohenfeld.snapledger.auth;

import java.time.Instant;
import java.util.UUID;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Table;

import lombok.AccessLevel;
import lombok.Getter;
import lombok.NoArgsConstructor;

import com.yulehohenfeld.snapledger.shared.persistence.AssignedIdEntity;

/** One session; revokedAt changes only via revoke. PT: Uma sessão; revokedAt muda só pelo revoke.
 *  Notes: docs/code-notes/auth.md#refreshtokenfamily */
@Entity
@Table(name = "refresh_token_families")
@Getter
@NoArgsConstructor(access = AccessLevel.PROTECTED) // JPA only
// PT: só para o JPA
public class RefreshTokenFamily extends AssignedIdEntity {

    @Column(name = "user_id", nullable = false, updatable = false)
    private UUID userId;

    @Column(name = "created_at", nullable = false, updatable = false)
    private Instant createdAt;

    @Column(name = "revoked_at")
    private Instant revokedAt;

    private RefreshTokenFamily(UUID id) {
        super(id);
    }

    /** A new, active session of {@code userId} (login or register).
     *  PT: Uma sessão nova e ativa de {@code userId} (login ou cadastro). */
    public static RefreshTokenFamily start(UUID userId, Instant now) {
        var family = new RefreshTokenFamily(UUID.randomUUID());
        family.userId = userId;
        family.createdAt = now;
        return family;
    }

    @Override
    public String toString() {
        return "RefreshTokenFamily[id=" + getId() + ", userId=" + userId + "]";
    }
}
