package com.yulehohenfeld.snapledger.auth;

import java.time.Instant;
import java.util.Optional;
import java.util.UUID;

import jakarta.persistence.LockModeType;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;

/** Sessions; lock order is always family first, then tokens. PT: A ordem dos locks é sempre família, depois tokens.
 *  Notes: docs/code-notes/auth.md#refreshtokenfamilyrepository */
public interface RefreshTokenFamilyRepository extends JpaRepository<RefreshTokenFamily, UUID> {

    /** Call first in the rotation transaction, before markUsed. PT: Chame primeiro na transação da rotação, antes do markUsed.
     *  Notes: docs/code-notes/auth.md#lockactive */
    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("select f from RefreshTokenFamily f where f.id = :id and f.revokedAt is null")
    Optional<RefreshTokenFamily> lockActive(UUID id);

    /** Ends the session; 1 for the call that revoked it, 0 otherwise. PT: Encerra a sessão; 1 para quem revogou, 0 se não.
     *  Notes: docs/code-notes/auth.md#revoke */
    @Modifying(flushAutomatically = true, clearAutomatically = true)
    @Query("update RefreshTokenFamily f set f.revokedAt = :now where f.id = :id and f.revokedAt is null")
    int revoke(UUID id, Instant now);
}
