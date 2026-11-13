package com.yulehohenfeld.snapledger.shared.error;

import org.springframework.http.HttpStatus;

/**
 * Login failed. Thrown for an unknown email and for a wrong password alike, with the same detail,
 * so login never tells which emails have an account (contract). Carries no email.
 *
 * <p>PT: O login falhou. Lançada tanto para email desconhecido quanto para senha errada, com o mesmo
 * detalhe, para que o login nunca revele quais emails têm conta (contrato). Não carrega o email.
 */
public class InvalidCredentialsException extends ApiException {

    public InvalidCredentialsException() {
        super(HttpStatus.UNAUTHORIZED, Slugs.INVALID_CREDENTIALS, "Email or password is incorrect.");
    }
}
