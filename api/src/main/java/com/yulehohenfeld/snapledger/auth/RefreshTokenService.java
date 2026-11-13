package com.yulehohenfeld.snapledger.auth;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.security.SecureRandom;
import java.time.Clock;
import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.Base64;
import java.util.HexFormat;
import java.util.UUID;

import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;

import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import com.yulehohenfeld.snapledger.shared.error.InvalidRefreshTokenException;

/**
 * Opaque refresh tokens (ADR 0002); only their SHA-256 is ever stored.
 *
 * <p>PT: Refresh tokens opacos (ADR 0002); só o SHA-256 deles é gravado.
 * Notes: docs/code-notes/auth.md#refreshtokenservice
 */
@Slf4j
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

    /**
     * Consumes the token and issues the next one of the same session. Lock the family first (ADR
     * 0008); a lock timeout propagates as a 500, never a 401.
     *
     * <p>PT: Consome o token e emite o próximo da mesma sessão. Trava a família primeiro (ADR 0008);
     * um lock timeout se propaga como 500, nunca 401.
     * Notes: docs/code-notes/auth.md#rotate
     */
    // noRollbackFor: the reuse revocation must commit even though the call ends in a 401.
    // PT: noRollbackFor: a revogação por reuso precisa fazer commit mesmo a chamada terminando em 401.
    @Transactional(noRollbackFor = InvalidRefreshTokenException.class)
    public Rotation rotate(String rawToken) {
        var token = tokens.findByTokenHash(sha256(rawToken))
                .orElseThrow(InvalidRefreshTokenException::new);
        var family = families.lockActive(token.getFamilyId())
                .orElseThrow(InvalidRefreshTokenException::new);

        // Read after the lock, so a long wait cannot make an expired token look valid; micros as stored.
        // PT: Lido depois do lock, para que uma espera longa não faça um token vencido parecer válido;
        //     em micros, como é gravado.
        var now = clock.instant().truncatedTo(ChronoUnit.MICROS);
        if (!token.getExpiresAt().isAfter(now)) {
            throw new InvalidRefreshTokenException();
        }
        if (tokens.markUsed(token.getId(), now) == 0) {
            families.revoke(family.getId(), now);
            log.warn("Refresh token reuse detected; family revoked familyId={}", family.getId());
            throw new InvalidRefreshTokenException();
        }
        return new Rotation(family.getUserId(), issue(family.getId(), now));
    }

    /**
     * Logout: revokes the session of any known token, even used or expired; unknown is a no-op.
     *
     * <p>PT: Logout: revoga a sessão de qualquer token conhecido, mesmo usado ou vencido;
     * desconhecido não faz nada.
     * Notes: docs/code-notes/auth.md#revokefamilyof
     */
    @Transactional
    public void revokeFamilyOf(String rawToken) {
        tokens.findByTokenHash(sha256(rawToken))
                .ifPresent(token -> families.revoke(token.getFamilyId(), clock.instant()));
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

    /**
     * The owner of the rotated session and its new refresh token.
     *
     * <p>PT: O dono da sessão rotacionada e o novo refresh token dela.
     * Notes: docs/code-notes/auth.md#rotation
     */
    public record Rotation(UUID userId, IssuedToken refreshToken) {
    }
}
