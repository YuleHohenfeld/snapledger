package com.yulehohenfeld.snapledger.auth.entity;

import java.time.Instant;
import java.util.UUID;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Table;

import lombok.AccessLevel;
import lombok.Getter;
import lombok.NoArgsConstructor;

import com.yulehohenfeld.snapledger.shared.persistence.AssignedIdEntity;

/** The single live reset grant of a user (hash only); created by the repository upsert, spent by markUsed.
 *  PT: A única permissão de redefinição viva de um usuário (só o hash); criada pelo upsert do repositório, gasta pelo markUsed.
 *  Notes: docs/code-notes/auth.md#passwordresetgrant */
@Entity
@Table(name = "password_reset_grants")
@Getter
@NoArgsConstructor(access = AccessLevel.PROTECTED) // JPA only
// PT: só para o JPA
public class PasswordResetGrant extends AssignedIdEntity {

    @Column(name = "user_id", nullable = false, updatable = false)
    private UUID userId;

    @Column(name = "token_hash", nullable = false, updatable = false, length = 64)
    private String tokenHash;

    @Column(name = "expires_at", nullable = false, updatable = false)
    private Instant expiresAt;

    @Column(name = "used_at")
    private Instant usedAt;

    @Column(name = "created_at", nullable = false, updatable = false)
    private Instant createdAt;

    /** True while the grant is unused and not expired. PT: Verdadeiro enquanto a permissão não foi usada nem venceu. */
    public boolean isUsable(Instant now) {
        return usedAt == null && now.isBefore(expiresAt);
    }

    /** Spends the grant; the caller checked {@link #isUsable} under the row lock. PT: Gasta a permissão; quem chama conferiu o {@link #isUsable} sob o lock da linha. */
    public void markUsed(Instant now) {
        usedAt = now;
    }

    // Never the hash: it is the lookup key of a live credential. PT: Nunca o hash: ele é a chave de busca de uma credencial viva.
    @Override
    public String toString() {
        return "PasswordResetGrant[id=" + getId() + "]";
    }
}
