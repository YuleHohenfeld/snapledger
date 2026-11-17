package com.yulehohenfeld.snapledger.support;

import java.time.Instant;
import java.util.UUID;

import org.springframework.beans.BeanUtils;
import org.springframework.test.util.ReflectionTestUtils;

import com.yulehohenfeld.snapledger.auth.entity.PasswordResetGrant;

/**
 * Builds in-memory {@link PasswordResetGrant} rows for unit tests; production code only creates them
 * through the repository upsert.
 *
 * <p>PT: Monta linhas {@link PasswordResetGrant} em memória para testes unitários; o código de produção
 * só as cria pelo upsert do repositório.
 */
public final class PasswordResetGrantFixtures {

    private PasswordResetGrantFixtures() {
    }

    public static PasswordResetGrant row(UUID userId, String tokenHash, Instant createdAt, Instant expiresAt,
            Instant usedAt) {
        var grant = BeanUtils.instantiateClass(BeanUtils.getResolvableConstructor(PasswordResetGrant.class));
        ReflectionTestUtils.setField(grant, "id", UUID.randomUUID());
        ReflectionTestUtils.setField(grant, "userId", userId);
        ReflectionTestUtils.setField(grant, "tokenHash", tokenHash);
        ReflectionTestUtils.setField(grant, "createdAt", createdAt);
        ReflectionTestUtils.setField(grant, "expiresAt", expiresAt);
        ReflectionTestUtils.setField(grant, "usedAt", usedAt);
        return grant;
    }
}
