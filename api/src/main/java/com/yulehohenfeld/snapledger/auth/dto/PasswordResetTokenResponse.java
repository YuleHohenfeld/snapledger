package com.yulehohenfeld.snapledger.auth.dto;

/** Response of the reset code check: the one-use token and its lifetime in seconds.
 *  PT: Resposta da conferência do código: o token de uso único e a validade dele em segundos.
 *  Notes: docs/code-notes/auth.md#passwordresetservice */
public record PasswordResetTokenResponse(String resetToken, long expiresIn) {

    public static PasswordResetTokenResponse of(IssuedToken token) {
        return new PasswordResetTokenResponse(token.value(), token.ttl().toSeconds());
    }

    // The token is a credential. PT: O token é uma credencial.
    @Override
    public String toString() {
        return "PasswordResetTokenResponse[resetToken=****, expiresIn=" + expiresIn + "]";
    }
}
