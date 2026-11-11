package com.yulehohenfeld.snapledger.shared.error;

/**
 * The problem slugs of docs/api-contract.md "Errors", the only values allowed after
 * {@code urn:snapledger:problem:}. Production code refers to these constants so a typo is a
 * compile error; ProblemFactory maps each one to its fixed title. Adding a slug means adding it
 * to the contract first, then here and to ProblemFactory's title table.
 */
public final class Slugs {

    public static final String VALIDATION_ERROR = "validation-error";
    public static final String UNAUTHORIZED = "unauthorized";
    public static final String INVALID_CREDENTIALS = "invalid-credentials";
    public static final String INVALID_REFRESH_TOKEN = "invalid-refresh-token";
    public static final String FORBIDDEN = "forbidden";
    public static final String DEFAULT_CATEGORY_READ_ONLY = "default-category-read-only";
    public static final String NOT_FOUND = "not-found";
    public static final String METHOD_NOT_ALLOWED = "method-not-allowed";
    public static final String NOT_ACCEPTABLE = "not-acceptable";
    public static final String EMAIL_ALREADY_REGISTERED = "email-already-registered";
    public static final String CATEGORY_NAME_TAKEN = "category-name-taken";
    public static final String CATEGORY_IN_USE = "category-in-use";
    public static final String UNSUPPORTED_MEDIA_TYPE = "unsupported-media-type";
    public static final String INTERNAL_ERROR = "internal-error";

    private Slugs() {
    }
}
