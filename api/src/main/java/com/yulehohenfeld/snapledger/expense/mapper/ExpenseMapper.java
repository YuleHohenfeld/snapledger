package com.yulehohenfeld.snapledger.expense.mapper;

import org.mapstruct.Mapper;
import org.mapstruct.Mapping;

import com.yulehohenfeld.snapledger.category.mapper.CategoryMapper;
import com.yulehohenfeld.snapledger.expense.dto.ExpenseResponse;
import com.yulehohenfeld.snapledger.expense.entity.Expense;

/** Expense to ExpenseResponse only; the category is embedded through CategoryMapper.
 *  PT: Só Expense para ExpenseResponse; a categoria vem embutida pelo CategoryMapper.
 *  Notes: docs/code-notes/expense.md#expensemapper */
@Mapper(componentModel = "spring", uses = CategoryMapper.class)
public interface ExpenseMapper {

    @Mapping(target = "date", source = "expenseDate")
    ExpenseResponse toResponse(Expense expense);
}
