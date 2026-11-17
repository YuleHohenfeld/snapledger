package com.yulehohenfeld.snapledger.auth.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

import com.yulehohenfeld.snapledger.shared.validation.Utf8ByteSize;

/** Body of the reset confirmation: the token from verify and the new password (register rules).
 *  The token has no format check on purpose: a malformed one must be invalid-reset-token, like any other.
 *  PT: Corpo da confirmação: o token do verify e a senha nova (regras do cadastro). O token não tem
 *  checagem de formato de propósito: um malformado precisa ser invalid-reset-token, como qualquer outro.
 *  Notes: docs/code-notes/auth.md#passwordresetservice */
public record PasswordResetConfirmRequest(
        @NotBlank @Size(max = 256) String resetToken,
        @NotBlank @Utf8ByteSize(min = 8, max = 72) String newPassword) {

    // The token and the password are secrets: neither reaches a log.
    // PT: O token e a senha são segredos: nenhum chega a um log.
    @Override
    public String toString() {
        return "PasswordResetConfirmRequest[resetToken=****, newPassword=****]";
    }
}
