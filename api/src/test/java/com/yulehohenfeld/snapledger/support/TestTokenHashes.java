package com.yulehohenfeld.snapledger.support;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.HexFormat;

/**
 * Refresh token hashes for fixtures, computed here and not by RefreshTokenService, so a bug there
 * cannot hide in the expected value.
 *
 * <p>PT: Hashes de refresh token para os dados de teste, calculados aqui e não pelo
 * RefreshTokenService, para que um bug lá não se esconda no valor esperado.
 */
public final class TestTokenHashes {

    private TestTokenHashes() {
    }

    /**
     * Lowercase hex SHA-256, the form {@code ck_refresh_tokens_token_hash_hex} accepts.
     *
     * <p>PT: SHA-256 em hex minúsculo, a forma que o {@code ck_refresh_tokens_token_hash_hex} aceita.
     */
    public static String hashOf(String raw) {
        try {
            var digest = MessageDigest.getInstance("SHA-256").digest(raw.getBytes(StandardCharsets.UTF_8));
            return HexFormat.of().formatHex(digest);
        } catch (NoSuchAlgorithmException e) {
            throw new IllegalStateException(e);
        }
    }
}
