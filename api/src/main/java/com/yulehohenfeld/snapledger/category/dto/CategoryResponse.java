package com.yulehohenfeld.snapledger.category.dto;

import java.util.UUID;

import com.fasterxml.jackson.annotation.JsonProperty;

/** The contract's CategoryResponse; {@code key} is null for own categories.
 *  PT: O CategoryResponse do contrato; {@code key} é nulo nas categorias próprias.
 *  Notes: docs/code-notes/category.md#categoryresponse */
public record CategoryResponse(
        UUID id,
        String name,
        @JsonProperty("isDefault") boolean isDefault,
        String key) {

    // The name is user text: logs carry ids only.
    // PT: O nome é texto do usuário: os logs levam só ids.
    @Override
    public String toString() {
        return "CategoryResponse[id=" + id + ", isDefault=" + isDefault + ", key=" + key + "]";
    }
}
