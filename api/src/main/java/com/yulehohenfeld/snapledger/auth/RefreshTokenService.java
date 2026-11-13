package com.yulehohenfeld.snapledger.auth;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.security.SecureRandom;
import java.time.Clock;
import java.time.Instant;
import java.util.Base64;
import java.util.HexFormat;
import java.util.UUID;

import lombok.RequiredArgsConstructor;

import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * Opaque refresh tokens (ADR 0002); only their SHA-256 is ever stored.
 *
 * <p>PT: Refresh tokens opacos (ADR 0002); só o SHA-256 deles é gravado.
 * Notes: docs/code-notes/auth.md#refreshtokenservice
 */
@Service
@RequiredArgsConstructor
public class RefreshTokenService {

    /** 256 bits (contract). PT: 256 bits (contrato). */
    static final int TOKEN_BYTES = 32;

    private static final SecureRandom RANDOM = new SecureRandom();

    private final RefreshTokenRepository tokens;
    private final RefreshTokenFamilyRepository families;
    private final RefreshTokenProperties props;
    private final Clock clock;

    /**
     * New session for {@code userId}: a family row and its first token. Returns the raw token,
     * which exists only in this return value.
     *
     * <p>PT: Sessão nova para {@code userId}: uma linha de família e o primeiro token dela. Devolve o
     * token cru, que só existe neste valor de retorno.
     * Notes: docs/code-notes/auth.md#startfamily
     */
    @Transactional
    public IssuedToken startFamily(UUID userId) {
        var now = clock.instant();
        var family = families.save(RefreshTokenFamily.start(userId, now));
        return issue(family.getId(), now);
    }

    private IssuedToken issue(UUID familyId, Instant now) {
        var bytes = new byte[TOKEN_BYTES];
        RANDOM.nextBytes(bytes);
        var raw = Base64.getUrlEncoder().withoutPadding().encodeToString(bytes);
        var ttl = props.ttl();
        tokens.save(RefreshToken.issue(familyId, sha256(raw), now, now.plus(ttl)));
        return new IssuedToken(raw, ttl);
    }

    /**
     * Lowercase hex SHA-256 of the token, the form {@code ck_refresh_tokens_token_hash_hex} accepts.
     *
     * <p>PT: SHA-256 do token em hex minúsculo, a forma que {@code ck_refresh_tokens_token_hash_hex} aceita.
     */
    static String sha256(String raw) {
        try {
            var digest = MessageDigest.getInstance("SHA-256").digest(raw.getBytes(StandardCharsets.UTF_8));
            return HexFormat.of().formatHex(digest);
        } catch (NoSuchAlgorithmException e) {
            // Every Java platform must provide SHA-256, so this cannot happen.
            // PT: Toda plataforma Java precisa oferecer SHA-256, então isto não acontece.
            throw new IllegalStateException(e);
        }
    }
}
