package com.yulehohenfeld.snapledger.support;

import java.time.Duration;
import java.time.Instant;
import java.util.UUID;

import org.springframework.beans.BeanUtils;
import org.springframework.test.util.ReflectionTestUtils;

import com.yulehohenfeld.snapledger.accountcode.entity.AccountCode;
import com.yulehohenfeld.snapledger.accountcode.entity.CodePurpose;

/**
 * Builds in-memory {@link AccountCode} rows for unit tests, with the values the native insert writes.
 * Production code has no factory on purpose: rows are only created by the repository's insert.
 *
 * <p>PT: Monta linhas {@link AccountCode} em memória para testes unitários, com os valores que o insert
 * nativo grava. O código de produção não tem fábrica de propósito: linhas só nascem do insert do repositório.
 */
public final class AccountCodeFixtures {

    private AccountCodeFixtures() {
    }

    public static AccountCode row(UUID userId, CodePurpose purpose, String codeHash, Instant now, Duration ttl) {
        var code = BeanUtils.instantiateClass(BeanUtils.getResolvableConstructor(AccountCode.class));
        ReflectionTestUtils.setField(code, "id", UUID.randomUUID());
        ReflectionTestUtils.setField(code, "userId", userId);
        ReflectionTestUtils.setField(code, "purpose", purpose);
        ReflectionTestUtils.setField(code, "codeHash", codeHash);
        ReflectionTestUtils.setField(code, "sentAt", now);
        ReflectionTestUtils.setField(code, "expiresAt", now.plus(ttl));
        ReflectionTestUtils.setField(code, "windowStartedAt", now);
        ReflectionTestUtils.setField(code, "sendsInWindow", 1);
        ReflectionTestUtils.setField(code, "createdAt", now);
        return code;
    }
}
