package com.yulehohenfeld.snapledger.support;

import java.util.UUID;

import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;

/**
 * Real bcrypt hashes for test fixtures, so they pass {@code ck_users_password_hash_bcrypt} the way
 * production hashes do. Cost 4 (the minimum) keeps tests fast; the format is the same as cost 10.
 * The password is random per JVM: no literal secret in tests.
 *
 * <p>PT: Hashes bcrypt reais para os dados de teste, para que passem no
 * {@code ck_users_password_hash_bcrypt} como os hashes de produção passam. Custo 4 (o mínimo)
 * deixa os testes rápidos; o formato é o mesmo do custo 10. A senha é aleatória por JVM: nenhum
 * segredo literal nos testes.
 */
public final class TestPasswordHashes {

    /**
     * {@code $2a$04$} + 53 characters, as BCryptPasswordEncoder produces.
     *
     * <p>PT: {@code $2a$04$} + 53 caracteres, como o BCryptPasswordEncoder produz.
     */
    public static final String BCRYPT = new BCryptPasswordEncoder(4).encode(UUID.randomUUID().toString());

    private TestPasswordHashes() {
    }
}
