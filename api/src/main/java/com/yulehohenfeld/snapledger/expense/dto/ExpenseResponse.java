package com.yulehohenfeld.snapledger.expense.dto;

import java.math.BigDecimal;
import java.time.Instant;
import java.time.LocalDate;
import java.util.UUID;

import com.fasterxml.jackson.annotation.JsonFormat;

import com.yulehohenfeld.snapledger.category.dto.CategoryResponse;

/** The contract's ExpenseResponse; the amount is serialized as the string "12.50".
 *  PT: O ExpenseResponse do contrato; o valor é serializado como a string "12.50".
 *  Notes: docs/code-notes/expense.md#expenseresponse */
public record ExpenseResponse(
        UUID id,
        @JsonFormat(shape = JsonFormat.Shape.STRING) BigDecimal amount,
        String description,
        LocalDate date,
        CategoryResponse category,
        Instant createdAt,
        Instant updatedAt) {

    // Amount and description are personal financial data: logs carry ids only.
    // PT: Valor e descrição são dados financeiros pessoais: os logs levam só ids.
    @Override
    public String toString() {
        return "ExpenseResponse[id=" + id + ", date=" + date + "]";
    }
}
