package com.yulehohenfeld.snapledger.category.dto;

import jakarta.validation.constraints.NotBlank;

import com.yulehohenfeld.snapledger.shared.validation.CodePointLength;
import com.yulehohenfeld.snapledger.shared.validation.NoControlCharacters;

/** Body of POST and PATCH /categories; the name is trimmed before validation runs.
 *  PT: Corpo do POST e do PATCH /categories; o nome é aparado antes da validação.
 *  Notes: docs/code-notes/category.md#categoryrequest */
public record CategoryRequest(
        @NotBlank @CodePointLength(min = 1, max = 40) @NoControlCharacters String name) {

    public CategoryRequest {
        name = name == null ? null : name.strip();
    }

    // The name is user text: logs carry ids only.
    // PT: O nome é texto do usuário: os logs levam só ids.
    @Override
    public String toString() {
        return "CategoryRequest[name=****]";
    }
}
