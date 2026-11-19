package com.yulehohenfeld.snapledger.shared.error;

import org.springframework.http.HttpStatus;

/**
 * The category name is already used by a default or by one of the user's categories (409). The
 * detail names the field, never the value.
 *
 * <p>PT: O nome da categoria já é usado por uma padrão ou por uma do usuário (409). O detalhe cita
 * o campo, nunca o valor.
 * Notes: docs/code-notes/category.md#category-exceptions
 */
public class CategoryNameTakenException extends ApiException {

    public CategoryNameTakenException() {
        super(HttpStatus.CONFLICT, Slugs.CATEGORY_NAME_TAKEN, "The field 'name' is already used by another category.");
    }
}
