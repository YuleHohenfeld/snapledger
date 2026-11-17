package com.yulehohenfeld.snapledger.auth.repository;

import java.time.Instant;
import java.util.Optional;
import java.util.UUID;

import jakarta.persistence.LockModeType;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;

import com.yulehohenfeld.snapledger.auth.entity.PasswordResetGrant;

/** Reset grants; the unique user row is what makes "a new verify replaces the old grant" atomic.
 *  PT: A linha única por usuário torna atômico "um verify novo substitui a permissão antiga".
 *  Notes: docs/code-notes/auth.md#passwordresetgrantrepository */
public interface PasswordResetGrantRepository extends JpaRepository<PasswordResetGrant, UUID> {

    /** Credential lookup by token hash, without a lock: only to learn which user row to lock first (lock order).
     *  PT: Busca de credencial por hash, sem lock: só para saber qual linha de usuário travar primeiro (ordem de locks).
     *  Notes: docs/code-notes/auth.md#lock-order-of-the-reset-grant */
    @Query("select g.userId from PasswordResetGrant g where g.tokenHash = :tokenHash")
    Optional<UUID> findUserIdByTokenHash(String tokenHash);

    /** Call after the user lock, never before. PT: Chame depois do lock do usuário, nunca antes.
     *  Notes: docs/code-notes/auth.md#lock-order-of-the-reset-grant */
    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("select g from PasswordResetGrant g where g.tokenHash = :tokenHash")
    Optional<PasswordResetGrant> lockByTokenHash(String tokenHash);

    /** Creates the user's grant or replaces the previous one (new hash and expiry, use mark cleared); one statement, so atomic.
     *  PT: Cria a permissão do usuário ou substitui a anterior (hash e validade novos, marca de uso limpa); um comando só, então atômico.
     *  Notes: docs/code-notes/auth.md#lock-order-of-the-reset-grant */
    @Modifying(flushAutomatically = true, clearAutomatically = true)
    @Query(value = """
            insert into password_reset_grants (id, user_id, token_hash, expires_at, used_at, created_at)
            values (:id, :userId, :tokenHash, :expiresAt, null, :now)
            on conflict (user_id) do update
                set token_hash = excluded.token_hash, expires_at = excluded.expires_at,
                    used_at = null, created_at = excluded.created_at
            """, nativeQuery = true)
    int upsert(UUID id, UUID userId, String tokenHash, Instant expiresAt, Instant now);
}
