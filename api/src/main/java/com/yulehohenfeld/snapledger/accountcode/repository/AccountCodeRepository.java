package com.yulehohenfeld.snapledger.accountcode.repository;

import java.time.Instant;
import java.util.Optional;
import java.util.UUID;

import jakarta.persistence.LockModeType;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;

import com.yulehohenfeld.snapledger.accountcode.entity.AccountCode;
import com.yulehohenfeld.snapledger.accountcode.entity.CodePurpose;

/** Codes; the unique (user, purpose) row is what serializes issue and consume. PT: A linha única (usuário, finalidade) serializa emitir e consumir.
 *  Notes: docs/code-notes/account-code.md#accountcoderepository */
public interface AccountCodeRepository extends JpaRepository<AccountCode, UUID> {

    /** Call first in every issue and consume transaction. PT: Chame primeiro em toda transação de emitir e consumir.
     *  Notes: docs/code-notes/account-code.md#lock */
    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("select c from AccountCode c where c.userId = :userId and c.purpose = :purpose")
    Optional<AccountCode> lock(UUID userId, CodePurpose purpose);

    /** First code of a (user, purpose); 0 when a concurrent request already inserted the row (no exception, so the caller's transaction survives).
     *  PT: Primeiro código de um (usuário, finalidade); 0 quando uma requisição concorrente já inseriu a linha (sem exceção, então a transação de quem chama sobrevive).
     *  Notes: docs/code-notes/account-code.md#insertifabsent */
    @Modifying(flushAutomatically = true)
    @Query(value = """
            insert into account_codes (id, user_id, purpose, code_hash, sent_at, expires_at, attempts,
                                       window_started_at, sends_in_window, created_at)
            values (:id, :userId, :purpose, :codeHash, :now, :expiresAt, 0, :now, 1, :now)
            on conflict (user_id, purpose) do nothing
            """, nativeQuery = true)
    int insertIfAbsent(UUID id, UUID userId, String purpose, String codeHash, Instant now, Instant expiresAt);
}
