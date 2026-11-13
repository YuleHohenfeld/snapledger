package com.yulehohenfeld.snapledger.auth.dto;

import java.time.Duration;

/**
 * A token just issued and the lifetime it was issued with; the value is a live credential.
 *
 * <p>PT: Um token recém-emitido e a validade com que foi emitido; o valor é uma credencial viva.
 * Notes: docs/code-notes/auth.md#issuedtoken
 */
public record IssuedToken(String value, Duration ttl) {

    // Never the value: whoever reads a log line must not get a session.
    // PT: Nunca o valor: quem lê uma linha de log não pode ganhar uma sessão.
    @Override
    public String toString() {
        return "IssuedToken[value=****, ttl=" + ttl + "]";
    }
}
