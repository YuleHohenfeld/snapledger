package com.yulehohenfeld.snapledger.accountcode.config;

import java.security.MessageDigest;

import org.springframework.stereotype.Component;

import com.yulehohenfeld.snapledger.shared.security.JwtProperties;

/**
 * Stops startup when ACCOUNT_CODE_SECRET and JWT_SECRET decode to the same key; the message quotes neither.
 *
 * <p>PT: Impede a subida quando ACCOUNT_CODE_SECRET e JWT_SECRET decodificam para a mesma chave; a mensagem não cita nenhuma.
 * Notes: docs/code-notes/account-code.md#distinct-secrets
 */
@Component
class DistinctSecretsValidator {

    static final String SAME_SECRET =
            "app.account-code.secret (ACCOUNT_CODE_SECRET) must differ from app.security.jwt.secret (JWT_SECRET)";

    DistinctSecretsValidator(AccountCodeProperties accountCode, JwtProperties jwt) {
        if (MessageDigest.isEqual(accountCode.key().getEncoded(), jwt.key().getEncoded())) {
            throw new IllegalStateException(SAME_SECRET);
        }
    }
}
