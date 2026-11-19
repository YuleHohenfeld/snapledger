package com.yulehohenfeld.snapledger.expense.service;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.time.YearMonth;
import java.util.Comparator;
import java.util.UUID;

import lombok.RequiredArgsConstructor;

import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import com.yulehohenfeld.snapledger.expense.dto.ExpenseSummaryResponse;
import com.yulehohenfeld.snapledger.expense.dto.ExpenseSummaryResponse.CategorySummary;
import com.yulehohenfeld.snapledger.expense.repository.ExpenseCategoryTotal;
import com.yulehohenfeld.snapledger.expense.repository.ExpenseRepository;
import com.yulehohenfeld.snapledger.user.service.UserService;

/**
 * The monthly summary: per-category sums run in SQL (exact, on numeric); the month total adds those
 * exact sums here; only the percentage is rounded, in BigDecimal, HALF_UP (ADR 0015). One
 * read-only transaction; the two queries cover different months, so no mixed state is visible.
 *
 * <p>PT: O resumo mensal: as somas por categoria rodam no SQL (exatas, em numeric); o total do mês
 * soma essas somas exatas aqui; só o percentual é arredondado, em BigDecimal, HALF_UP (ADR 0015).
 * Uma transação só de leitura; as duas queries cobrem meses diferentes, então não há estado misto.
 * Notes: docs/code-notes/expense.md#expensesummaryservice
 */
@Service
@RequiredArgsConstructor
public class ExpenseSummaryService {

    private static final BigDecimal HUNDRED = BigDecimal.valueOf(100);
    private static final int MONEY_SCALE = 2;

    private final ExpenseRepository expenses;
    private final UserService users;

    @Transactional(readOnly = true)
    public ExpenseSummaryResponse summarize(UUID userId, YearMonth month) {
        var currency = users.getCurrent(userId).currency();
        var from = month.atDay(1);
        var to = month.plusMonths(1).atDay(1);

        var rows = expenses.sumByCategory(userId, from, to);
        var previous = expenses.sumBetween(userId, month.minusMonths(1).atDay(1), from);

        // Adding exact sums is exact. PT: Somar somas exatas é exato.
        var total = rows.stream().map(ExpenseCategoryTotal::total).reduce(BigDecimal.ZERO, BigDecimal::add);
        var count = rows.stream().mapToLong(ExpenseCategoryTotal::expenseCount).sum();

        var byCategory = rows.stream()
                .sorted(Comparator.comparing(ExpenseCategoryTotal::total).reversed()
                        .thenComparing(ExpenseCategoryTotal::categoryName, String.CASE_INSENSITIVE_ORDER)
                        // The id text is a stable last resort (same order on every JVM and database).
                        // PT: O texto do id é o último critério estável (mesma ordem em qualquer JVM e banco).
                        .thenComparing(row -> row.categoryId().toString()))
                .map(row -> new CategorySummary(row.categoryId(), row.categoryName(), money(row.total()),
                        row.expenseCount(), percentage(row.total(), total)))
                .toList();

        return new ExpenseSummaryResponse(month.toString(), currency, money(total), count, money(previous), byCategory);
    }

    /** Never divides by zero: an empty month has no categories, and a zero total reads 0.00.
     *  PT: Nunca divide por zero: mês vazio não tem categorias, e total zero vira 0.00. */
    private static BigDecimal percentage(BigDecimal part, BigDecimal whole) {
        if (whole.signum() == 0) {
            return money(BigDecimal.ZERO);
        }
        return part.multiply(HUNDRED).divide(whole, MONEY_SCALE, RoundingMode.HALF_UP);
    }

    private static BigDecimal money(BigDecimal value) {
        return value.setScale(MONEY_SCALE, RoundingMode.UNNECESSARY);
    }
}
