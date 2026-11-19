package com.yulehohenfeld.snapledger.shared.error;

import org.springframework.http.HttpStatus;

/**
 * Delete of a category that still has expenses (409).
 *
 * <p>PT: Apagar uma categoria que ainda tem despesas (409).
 * Notes: docs/code-notes/category.md#category-exceptions
 */
public class CategoryInUseException extends ApiException {

    public CategoryInUseException() {
        super(HttpStatus.CONFLICT, Slugs.CATEGORY_IN_USE, "The category still has expenses.");
    }
}
