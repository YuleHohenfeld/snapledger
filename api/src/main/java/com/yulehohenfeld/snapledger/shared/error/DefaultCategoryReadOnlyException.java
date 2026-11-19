package com.yulehohenfeld.snapledger.shared.error;

import org.springframework.http.HttpStatus;

/**
 * Rename or delete of a default category (403); defaults change only by migration.
 *
 * <p>PT: Renomear ou apagar uma categoria padrão (403); as padrão só mudam por migration.
 * Notes: docs/code-notes/category.md#category-exceptions
 */
public class DefaultCategoryReadOnlyException extends ApiException {

    public DefaultCategoryReadOnlyException() {
        super(HttpStatus.FORBIDDEN, Slugs.DEFAULT_CATEGORY_READ_ONLY, "Default categories cannot be changed.");
    }
}
