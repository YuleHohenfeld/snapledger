package com.yulehohenfeld.snapledger.expense.repository;

import java.math.BigDecimal;
import java.util.UUID;

/** One row of the month summary query: a category with its sum and count in the month.
 *  PT: Uma linha da consulta do resumo do mês: uma categoria com a soma e a contagem no mês.
 *  Notes: docs/code-notes/expense.md#summary-query */
public record ExpenseCategoryTotal(UUID categoryId, String categoryName, BigDecimal total, long expenseCount) {

    // Totals are personal financial data: logs carry ids only. PT: Totais são dados financeiros pessoais: os logs levam só ids.
    @Override
    public String toString() {
        return "ExpenseCategoryTotal[categoryId=" + categoryId + "]";
    }
}
