package com.yulehohenfeld.snapledger.auth.dto;

import jakarta.validation.constraints.NotNull;

import com.yulehohenfeld.snapledger.shared.validation.ValidCode;
import com.yulehohenfeld.snapledger.shared.validation.ValidEmail;

/** Body of the reset code check. PT: Corpo da conferência do código de redefinição.
 *  Notes: docs/code-notes/auth.md#passwordresetservice */
public record PasswordResetVerifyRequest(@NotNull @ValidEmail String email, @NotNull @ValidCode String code) {

    // Email is personal data and the code a secret: neither reaches a log.
    // PT: O email é dado pessoal e o código um segredo: nenhum chega a um log.
    @Override
    public String toString() {
        return "PasswordResetVerifyRequest[email=****, code=****]";
    }
}
