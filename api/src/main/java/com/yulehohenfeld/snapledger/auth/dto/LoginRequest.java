package com.yulehohenfeld.snapledger.auth.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;

import com.yulehohenfeld.snapledger.shared.validation.Utf8ByteSize;
import com.yulehohenfeld.snapledger.shared.validation.ValidEmail;

/** Login body; never enforces the password policy. PT: Corpo do login; nunca aplica a política de senha.
 *  Notes: docs/code-notes/auth.md#loginrequest */
public record LoginRequest(
        @NotNull @ValidEmail String email,
        @NotBlank @Utf8ByteSize(max = 72) String password) {

    // Email is personal data and the password a secret: neither reaches a log.
    // PT: O email é dado pessoal e a senha um segredo: nenhum dos dois chega a um log.
    @Override
    public String toString() {
        return "LoginRequest[email=****, password=****]";
    }
}
