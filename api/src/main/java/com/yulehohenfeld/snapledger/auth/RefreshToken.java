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

/** One refresh token (hash only); usedAt changes only via markUsed. PT: Um refresh token (só o hash); usedAt muda só pelo markUsed.
 *  Notes: docs/code-notes/auth.md#refreshtoken */
@Entity
@Table(name = "refresh_tokens")
@Getter
@NoArgsConstructor(access = AccessLevel.PROTECTED) // JPA only
// PT: só para o JPA
public class RefreshToken extends AssignedIdEntity {

    @Column(name = "family_id", nullable = false, updatable = false)
    private UUID familyId;

    @Column(name = "token_hash", nullable = false, updatable = false, length = 64)
    private String tokenHash;

    @Column(name = "expires_at", nullable = false, updatable = false)
    private Instant expiresAt;

    @Column(name = "used_at")
    private Instant usedAt;

    @Column(name = "created_at", nullable = false, updatable = false)
    private Instant createdAt;

    private RefreshToken(UUID id) {
        super(id);
    }

    /** A new unused token; {@code tokenHash} is the hex SHA-256, never the raw token.
     *  PT: Um token novo não usado; {@code tokenHash} é o SHA-256 em hex, nunca o token cru. */
    public static RefreshToken issue(UUID familyId, String tokenHash, Instant now, Instant expiresAt) {
        var token = new RefreshToken(UUID.randomUUID());
        token.familyId = familyId;
        token.tokenHash = tokenHash;
        token.createdAt = now;
        token.expiresAt = expiresAt;
        return token;
    }

    // Never the hash: it is the lookup key of a live session.
    // PT: Nunca o hash: ele é a chave de busca de uma sessão viva.
    @Override
    public String toString() {
        return "RefreshToken[id=" + getId() + ", familyId=" + familyId + "]";
    }
}
