package com.yulehohenfeld.snapledger.shared.error;

import org.springframework.http.HttpStatus;

/**
 * Base class of every domain error. The slug must exist in docs/api-contract.md "Errors";
 * GlobalExceptionHandler turns it into a ProblemDetail. Services throw these and never
 * build HTTP responses themselves.
 */
public abstract class ApiException extends RuntimeException {

    private final HttpStatus status;
    private final String slug;

    /**
     * @throws IllegalArgumentException if the slug is not in the contract, so a wrong subclass
     *         fails the first time it is constructed instead of while its error is being rendered
     */
    protected ApiException(HttpStatus status, String slug, String detail) {
        super(detail);
        this.status = status;
        this.slug = ProblemFactory.requireKnownSlug(slug);
    }

    public HttpStatus status() {
        return status;
    }

    public String slug() {
        return slug;
    }
}
