package com.yulehohenfeld.snapledger.auth.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;

import com.yulehohenfeld.snapledger.shared.validation.CodePointLength;
import com.yulehohenfeld.snapledger.shared.validation.NoControlCharacters;
import com.yulehohenfeld.snapledger.shared.validation.Utf8ByteSize;
import com.yulehohenfeld.snapledger.shared.validation.ValidCurrency;
import com.yulehohenfeld.snapledger.shared.validation.ValidEmail;

/** Register body; the name is trimmed before validation runs. PT: O nome é aparado antes da validação.
 *  Notes: docs/code-notes/auth.md#registerrequest */
public record RegisterRequest(
        @NotBlank @CodePointLength(min = 1, max = 80) @NoControlCharacters String name,
        @NotNull @ValidEmail String email,
        @NotBlank @Utf8ByteSize(min = 8, max = 72) String password,
        @ValidCurrency String currency) {

    /** Currency of an account when the request omits it (contract).
     *  PT: Moeda de uma conta quando a requisição não a envia (contrato). */
    public static final String DEFAULT_CURRENCY = "BRL";

    public RegisterRequest {
        name = name == null ? null : name.strip();
        currency = currency == null ? DEFAULT_CURRENCY : currency;
    }

    // Password, email and name never reach a log: one is a secret, the others are personal data.
    // PT: Senha, email e nome nunca chegam a um log: um é segredo, os outros são dados pessoais.
    @Override
    public String toString() {
        return "RegisterRequest[name=****, email=****, password=****, currency=" + currency + "]";
    }
}
