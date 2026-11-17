package com.yulehohenfeld.snapledger.auth.dto;

import jakarta.validation.constraints.NotNull;

import com.yulehohenfeld.snapledger.shared.validation.ValidEmail;

/** Body of the reset code request. PT: Corpo do pedido do código de redefinição.
 *  Notes: docs/code-notes/auth.md#passwordresetservice */
public record PasswordResetRequest(@NotNull @ValidEmail String email) {

    // Email is personal data: it never reaches a log. PT: O email é dado pessoal: nunca chega a um log.
    @Override
    public String toString() {
        return "PasswordResetRequest[email=****]";
    }
}
