package com.yulehohenfeld.snapledger.shared.error;

import org.springframework.http.HttpStatus;

/**
 * An email or password reset code was refused: wrong, expired, used, exhausted, replaced, unknown
 * account... deliberately one fixed answer (contract). Carries no code and no cause.
 *
 * <p>PT: Um código de email ou de redefinição de senha foi recusado: errado, vencido, usado,
 * esgotado, substituído, conta desconhecida... de propósito uma resposta fixa só (contrato). Não
 * carrega código nem causa.
 * Notes: docs/code-notes/account-code.md#invalidcodeexception
 */
public class InvalidCodeException extends ApiException {

    public InvalidCodeException() {
        super(HttpStatus.BAD_REQUEST, Slugs.INVALID_CODE, "The code is not valid.");
    }
}
