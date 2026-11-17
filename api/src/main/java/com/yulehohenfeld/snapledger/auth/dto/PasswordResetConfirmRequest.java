package com.yulehohenfeld.snapledger.auth.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;

import com.yulehohenfeld.snapledger.shared.validation.Utf8ByteSize;
import com.yulehohenfeld.snapledger.shared.validation.ValidCode;
import com.yulehohenfeld.snapledger.shared.validation.ValidEmail;

/** Body of the reset confirmation; the new password follows the register rules.
 *  PT: Corpo da confirmação da redefinição; a senha nova segue as regras do cadastro.
 *  Notes: docs/code-notes/auth.md#passwordresetservice */
public record PasswordResetConfirmRequest(
        @NotNull @ValidEmail String email,
        @NotNull @ValidCode String code,
        @NotBlank @Utf8ByteSize(min = 8, max = 72) String newPassword) {

    // Email is personal data, the code and the password are secrets: none reaches a log.
    // PT: O email é dado pessoal, o código e a senha são segredos: nenhum chega a um log.
    @Override
    public String toString() {
        return "PasswordResetConfirmRequest[email=****, code=****, newPassword=****]";
    }
}
