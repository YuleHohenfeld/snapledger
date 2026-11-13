package com.yulehohenfeld.snapledger.auth.dto;

import jakarta.validation.constraints.NotBlank;

import com.yulehohenfeld.snapledger.shared.validation.CodePointLength;

/** Refresh and logout body; any other shape is just an unknown token. PT: Qualquer outro formato é só um token desconhecido.
 *  Notes: docs/code-notes/auth.md#refreshrequest */
public record RefreshRequest(@NotBlank @CodePointLength(max = 256) String refreshToken) {

    // The refresh token is a live credential: it never reaches a log.
    // PT: O refresh token é uma credencial viva: ele nunca chega a um log.
    @Override
    public String toString() {
        return "RefreshRequest[refreshToken=****]";
    }
}
