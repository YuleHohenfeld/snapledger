package com.yulehohenfeld.snapledger.shared.error;

import org.springframework.http.HttpStatus;

/**
 * Refresh failed: unknown, expired, revoked or reused, deliberately one fixed answer (contract).
 * Carries no token and no cause.
 *
 * <p>PT: O refresh falhou: desconhecido, vencido, revogado ou reusado, de propósito uma resposta
 * fixa só (contrato). Não carrega token nem causa.
 * Notes: docs/code-notes/auth.md#invalidrefreshtokenexception
 */
public class InvalidRefreshTokenException extends ApiException {

    public InvalidRefreshTokenException() {
        super(HttpStatus.UNAUTHORIZED, Slugs.INVALID_REFRESH_TOKEN, "The refresh token is not valid.");
    }
}
