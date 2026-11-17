package com.yulehohenfeld.snapledger.shared.ratelimit;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.HexFormat;
import java.util.Locale;

/**
 * Limiter keys that must not hold personal data.
 *
 * <p>PT: Chaves do limitador que não podem guardar dados pessoais.
 * Notes: docs/code-notes/security.md#rate-limiting
 */
public final class RateLimitKeys {

    private RateLimitKeys() {
    }

    /** SHA-256 hex of the lowercase email, so the limiter never holds the address itself.
     *  PT: SHA-256 em hex do email em minúsculas, para o limitador nunca guardar o endereço. */
    public static String ofEmail(String email) {
        try {
            var digest = MessageDigest.getInstance("SHA-256")
                    .digest(email.toLowerCase(Locale.ROOT).getBytes(StandardCharsets.UTF_8));
            return HexFormat.of().formatHex(digest);
        } catch (NoSuchAlgorithmException e) {
            // Every Java platform must provide SHA-256, so this cannot happen.
            // PT: Toda plataforma Java precisa oferecer SHA-256, então isto não acontece.
            throw new IllegalStateException(e);
        }
    }
}
