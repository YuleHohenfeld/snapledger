package com.yulehohenfeld.snapledger.accountcode.service;

import java.nio.charset.StandardCharsets;
import java.security.GeneralSecurityException;
import java.security.MessageDigest;
import java.util.HexFormat;
import java.util.UUID;

import javax.crypto.Mac;

import org.springframework.stereotype.Component;

import com.yulehohenfeld.snapledger.accountcode.config.AccountCodeProperties;
import com.yulehohenfeld.snapledger.accountcode.entity.CodePurpose;

/**
 * HMAC-SHA256 of {@code purpose|userId|code} in lowercase hex, keyed by ACCOUNT_CODE_SECRET; compares in constant time.
 *
 * <p>PT: HMAC-SHA256 de {@code purpose|userId|code} em hex minúsculo, com a chave ACCOUNT_CODE_SECRET; compara em tempo constante.
 * Notes: docs/code-notes/account-code.md#accountcodehasher
 */
@Component
public class AccountCodeHasher {

    private static final String ALGORITHM = "HmacSHA256";

    private final AccountCodeProperties properties;

    public AccountCodeHasher(AccountCodeProperties properties) {
        this.properties = properties;
    }

    public String hash(CodePurpose purpose, UUID userId, String code) {
        try {
            // A Mac is not thread-safe, so one per call. PT: Um Mac não é thread-safe, então um por chamada.
            var mac = Mac.getInstance(ALGORITHM);
            mac.init(properties.key());
            var input = purpose.name() + "|" + userId + "|" + code;
            return HexFormat.of().formatHex(mac.doFinal(input.getBytes(StandardCharsets.UTF_8)));
        } catch (GeneralSecurityException e) {
            // HmacSHA256 is mandatory in every JVM; the message is left out on purpose.
            // PT: HmacSHA256 é obrigatório em toda JVM; a mensagem fica de fora de propósito.
            throw new IllegalStateException("HmacSHA256 is not available");
        }
    }

    /** True when {@code code} hashes to {@code storedHash}; never short-circuits on the first different byte.
     *  PT: Verdadeiro quando {@code code} gera {@code storedHash}; nunca para no primeiro byte diferente. */
    public boolean matches(CodePurpose purpose, UUID userId, String code, String storedHash) {
        var expected = storedHash.getBytes(StandardCharsets.US_ASCII);
        var actual = hash(purpose, userId, code).getBytes(StandardCharsets.US_ASCII);
        return MessageDigest.isEqual(expected, actual);
    }
}
