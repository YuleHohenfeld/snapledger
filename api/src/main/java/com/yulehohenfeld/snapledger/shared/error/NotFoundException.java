package com.yulehohenfeld.snapledger.shared.error;

import org.springframework.http.HttpStatus;

/**
 * Resource does not exist or belongs to another user: both cases are indistinguishable (404).
 *
 * <p>PT: O recurso não existe ou pertence a outro usuário: os dois casos são indistinguíveis (404).
 */
public class NotFoundException extends ApiException {

    public NotFoundException() {
        super(HttpStatus.NOT_FOUND, Slugs.NOT_FOUND, "Resource not found.");
    }
}
