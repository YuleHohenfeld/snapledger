package com.yulehohenfeld.snapledger.shared.error;

import org.springframework.http.HttpStatus;

/**
 * The access token was valid, but its user no longer exists (contract, {@code GET /users/me}):
 * the credential no longer identifies anyone, so the app must log in again. An ApiException, not
 * Spring's AuthenticationException: GlobalExceptionHandler rethrows the latter to the security
 * layer.
 *
 * <p>PT: O token de acesso era válido, mas o usuário dele não existe mais (contrato,
 * {@code GET /users/me}): a credencial não identifica mais ninguém, então o app precisa fazer login
 * de novo. É uma ApiException, e não a AuthenticationException do Spring: o GlobalExceptionHandler
 * relança esta última para a camada de segurança.
 */
public class UnauthorizedException extends ApiException {

    public UnauthorizedException() {
        super(HttpStatus.UNAUTHORIZED, Slugs.UNAUTHORIZED, "A valid access token is required.");
    }
}
