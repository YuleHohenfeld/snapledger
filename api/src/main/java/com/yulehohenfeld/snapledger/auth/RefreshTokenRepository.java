package com.yulehohenfeld.snapledger.auth;

import java.time.Instant;
import java.util.Optional;
import java.util.UUID;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;

/** Refresh tokens; consuming one is an atomic conditional update. PT: Consumir um token é um update condicional atômico.
 *  Notes: docs/code-notes/auth.md#refreshtokenrepository */
public interface RefreshTokenRepository extends JpaRepository<RefreshToken, UUID> {

    /** Lookup by the hex SHA-256 of the presented token. PT: Busca pelo SHA-256 em hex do token apresentado. */
    Optional<RefreshToken> findByTokenHash(String tokenHash);

    /** Atomic "spend once": check expiry and lockActive first, so 0 means reuse. PT: "gastar uma vez" atômico; 0 = reuso.
     *  Notes: docs/code-notes/auth.md#markused */
    @Modifying(flushAutomatically = true, clearAutomatically = true)
    @Query("""
           update RefreshToken t set t.usedAt = :now
           where t.id = :id
             and t.usedAt is null
             and t.expiresAt > :now
             and exists (select f.id from RefreshTokenFamily f
                         where f.id = t.familyId and f.revokedAt is null)
           """)
    int markUsed(UUID id, Instant now);
}
