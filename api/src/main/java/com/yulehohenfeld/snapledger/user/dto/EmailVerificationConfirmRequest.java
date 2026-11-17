package com.yulehohenfeld.snapledger.user.dto;

import jakarta.validation.constraints.NotNull;

import com.yulehohenfeld.snapledger.shared.validation.ValidCode;

/** Body of the email verification confirmation. PT: Corpo da confirmação da verificação de email.
 *  Notes: docs/code-notes/user.md#emailverificationservice */
public record EmailVerificationConfirmRequest(@NotNull @ValidCode String code) {

    // The code is a secret: it never reaches a log. PT: O código é um segredo: nunca chega a um log.
    @Override
    public String toString() {
        return "EmailVerificationConfirmRequest[code=****]";
    }
}
