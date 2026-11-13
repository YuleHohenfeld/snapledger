package com.yulehohenfeld.snapledger.auth.dto;

import java.time.Duration;

/** The contract's TokenResponse; lifetimes in seconds. PT: O TokenResponse do contrato; validades em segundos.
 *  Notes: docs/code-notes/auth.md#tokenresponse */
public record TokenResponse(
        String accessToken,
        String tokenType,
        long expiresIn,
        String refreshToken,
        long refreshExpiresIn) {

    public static final String BEARER = "Bearer";

    /** Always "Bearer"; lifetimes from the TTLs that set the expiry. PT: Sempre "Bearer"; validades dos TTLs da expiração.
     *  Notes: docs/code-notes/auth.md#bearer */
    public static TokenResponse bearer(String accessToken, Duration accessTtl,
                                       String refreshToken, Duration refreshTtl) {
        return new TokenResponse(accessToken, BEARER, accessTtl.toSeconds(), refreshToken, refreshTtl.toSeconds());
    }

    // Both tokens are credentials: a response logged by mistake must not hand out a session.
    // PT: Os dois tokens são credenciais: uma resposta registrada por engano não pode entregar uma sessão.
    @Override
    public String toString() {
        return "TokenResponse[accessToken=****, tokenType=%s, expiresIn=%d, refreshToken=****, refreshExpiresIn=%d]"
                .formatted(tokenType, expiresIn, refreshExpiresIn);
    }
}
