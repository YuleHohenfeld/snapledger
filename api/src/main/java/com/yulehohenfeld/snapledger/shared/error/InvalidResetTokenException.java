package com.yulehohenfeld.snapledger.shared.error;

import org.springframework.http.HttpStatus;

/**
 * A password reset token was refused: unknown, expired, used or replaced. One fixed answer, so the
 * app sends the user back to the start. Carries no token and no cause.
 *
 * <p>PT: Um token de redefinição de senha foi recusado: desconhecido, vencido, usado ou substituído.
 * Uma resposta fixa só, para o app mandar o usuário de volta ao início. Não carrega token nem causa.
 * Notes: docs/code-notes/account-code.md#invalidcodeexception
 */
public class InvalidResetTokenException extends ApiException {

    public InvalidResetTokenException() {
        super(HttpStatus.BAD_REQUEST, Slugs.INVALID_RESET_TOKEN, "The reset token is not valid.");
    }
}
