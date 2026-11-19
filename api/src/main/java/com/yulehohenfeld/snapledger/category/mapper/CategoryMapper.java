package com.yulehohenfeld.snapledger.category.mapper;

import org.mapstruct.Mapper;
import org.mapstruct.Mapping;

import com.yulehohenfeld.snapledger.category.dto.CategoryResponse;
import com.yulehohenfeld.snapledger.category.entity.Category;

/** Category to CategoryResponse only. PT: Só Category para CategoryResponse.
 *  Notes: docs/code-notes/category.md#categorymapper */
@Mapper(componentModel = "spring")
public interface CategoryMapper {

    // The record component is "isDefault", the entity getter is isDefault(): named explicitly.
    // PT: O componente do record é "isDefault" e o getter da entidade é isDefault(): nomeado explicitamente.
    @Mapping(target = "isDefault", expression = "java(category.isDefault())")
    CategoryResponse toResponse(Category category);
}
