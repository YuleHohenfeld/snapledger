package com.yulehohenfeld.snapledger.expense.dto;

import java.math.BigDecimal;
import java.util.List;
import java.util.UUID;

import com.fasterxml.jackson.annotation.JsonFormat;

/** The contract's summary; money and percentages are strings with 2 places ("1234.56").
 *  PT: O resumo do contrato; dinheiro e percentuais são strings com 2 casas ("1234.56").
 *  Notes: docs/code-notes/expense.md#expensesummaryresponse */
public record ExpenseSummaryResponse(
        String month,
        String currency,
        @JsonFormat(shape = JsonFormat.Shape.STRING) BigDecimal total,
        long expenseCount,
        @JsonFormat(shape = JsonFormat.Shape.STRING) BigDecimal previousMonthTotal,
        List<CategorySummary> byCategory) {

    /** One category of the month. PT: Uma categoria do mês. */
    public record CategorySummary(
            UUID categoryId,
            String categoryName,
            @JsonFormat(shape = JsonFormat.Shape.STRING) BigDecimal total,
            long expenseCount,
            @JsonFormat(shape = JsonFormat.Shape.STRING) BigDecimal percentage) {
    }

    // Totals are personal financial data: logs carry the month only. PT: Totais são dados financeiros pessoais: os logs levam só o mês.
    @Override
    public String toString() {
        return "ExpenseSummaryResponse[month=" + month + "]";
    }
}
