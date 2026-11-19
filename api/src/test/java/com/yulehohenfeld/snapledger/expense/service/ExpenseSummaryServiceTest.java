package com.yulehohenfeld.snapledger.expense.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.when;

import java.math.BigDecimal;
import java.time.Instant;
import java.time.LocalDate;
import java.time.YearMonth;
import java.util.List;
import java.util.UUID;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import com.yulehohenfeld.snapledger.expense.dto.ExpenseSummaryResponse.CategorySummary;
import com.yulehohenfeld.snapledger.expense.repository.ExpenseCategoryTotal;
import com.yulehohenfeld.snapledger.expense.repository.ExpenseRepository;
import com.yulehohenfeld.snapledger.user.dto.UserResponse;
import com.yulehohenfeld.snapledger.user.service.UserService;

/**
 * Summary rules with the repository and the user service mocked: percentage rounding, zero total,
 * ordering, month bounds.
 *
 * <p>PT: Regras do resumo com o repository e o service de usuário simulados: arredondamento do
 * percentual, total zero, ordenação, limites do mês.
 */
@ExtendWith(MockitoExtension.class)
class ExpenseSummaryServiceTest {

    static final YearMonth NOVEMBER = YearMonth.of(2026, 11);
    static final LocalDate FROM = LocalDate.of(2026, 11, 1);
    static final LocalDate TO = LocalDate.of(2026, 12, 1);

    @Mock
    ExpenseRepository expenses;

    @Mock
    UserService users;

    ExpenseSummaryService service;

    final UUID userId = UUID.randomUUID();

    @BeforeEach
    void createService() {
        service = new ExpenseSummaryService(expenses, users);
        when(users.getCurrent(userId)).thenReturn(new UserResponse(userId, "Ana", "ana@example.com", "EUR",
                Instant.parse("2026-01-01T00:00:00Z"), true));
    }

    @Test
    void anEmptyMonthIsZeroWithNoCategoriesAndTheUsersCurrency() {
        when(expenses.sumByCategory(userId, FROM, TO)).thenReturn(List.of());
        when(expenses.sumBetween(userId, LocalDate.of(2026, 10, 1), FROM)).thenReturn(BigDecimal.ZERO);

        var summary = service.summarize(userId, NOVEMBER);

        assertThat(summary.month()).isEqualTo("2026-11");
        assertThat(summary.currency()).isEqualTo("EUR");
        assertThat(summary.total()).isEqualTo(new BigDecimal("0.00"));
        assertThat(summary.expenseCount()).isZero();
        assertThat(summary.previousMonthTotal()).isEqualTo(new BigDecimal("0.00"));
        assertThat(summary.byCategory()).isEmpty();
    }

    @Test
    void januaryAsksForDecemberOfThePreviousYear() {
        when(expenses.sumByCategory(userId, LocalDate.of(2027, 1, 1), LocalDate.of(2027, 2, 1))).thenReturn(List.of());
        when(expenses.sumBetween(userId, LocalDate.of(2026, 12, 1), LocalDate.of(2027, 1, 1)))
                .thenReturn(new BigDecimal("980.5"));

        var summary = service.summarize(userId, YearMonth.of(2027, 1));

        assertThat(summary.previousMonthTotal()).isEqualTo(new BigDecimal("980.50"));
    }

    @Test
    void totalsAndCountsAddUpAndEverythingHasTwoPlaces() {
        stub(row("Food", "0.10", 1), row("Transport", "0.20", 2));

        var summary = service.summarize(userId, NOVEMBER);

        assertThat(summary.total()).isEqualTo(new BigDecimal("0.30"));
        assertThat(summary.expenseCount()).isEqualTo(3);
        assertThat(summary.byCategory()).extracting(CategorySummary::total)
                .containsExactly(new BigDecimal("0.20"), new BigDecimal("0.10"));
    }

    @Test
    void percentageIsRoundedHalfUpInBigDecimal() {
        // 1/3 = 33.333.. -> 33.33, 2/3 = 66.666.. -> 66.67.
        stub(row("A", "1.00", 1), row("B", "2.00", 1));

        var thirds = service.summarize(userId, NOVEMBER).byCategory();

        assertThat(thirds).extracting(CategorySummary::percentage)
                .containsExactly(new BigDecimal("66.67"), new BigDecimal("33.33"));
    }

    @Test
    void aHalfPercentRoundsUpNotToEven() {
        // 0.01 of 8.00 = 0.125% -> 0.13 with HALF_UP (HALF_EVEN would give 0.12).
        stub(row("Small", "0.01", 1), row("Big", "7.99", 1));

        var byCategory = service.summarize(userId, NOVEMBER).byCategory();

        assertThat(byCategory.get(1).categoryName()).isEqualTo("Small");
        assertThat(byCategory.get(1).percentage()).isEqualTo(new BigDecimal("0.13"));
    }

    @Test
    void aZeroTotalDoesNotDivideByZero() {
        stub(row("Free", "0.00", 2));

        var summary = service.summarize(userId, NOVEMBER);

        assertThat(summary.total()).isEqualTo(new BigDecimal("0.00"));
        assertThat(summary.byCategory()).singleElement()
                .satisfies(c -> assertThat(c.percentage()).isEqualTo(new BigDecimal("0.00")));
    }

    @Test
    void orderIsTotalDescThenNameThenId() {
        var low = UUID.fromString("00000000-0000-4000-8000-000000000001");
        var high = UUID.fromString("00000000-0000-4000-8000-000000000002");
        when(expenses.sumByCategory(userId, FROM, TO)).thenReturn(List.of(
                new ExpenseCategoryTotal(high, "Same", new BigDecimal("5.00"), 1),
                new ExpenseCategoryTotal(low, "Same", new BigDecimal("5.00"), 1),
                new ExpenseCategoryTotal(UUID.randomUUID(), "Beta", new BigDecimal("5.00"), 1),
                new ExpenseCategoryTotal(UUID.randomUUID(), "Top", new BigDecimal("9.00"), 1)));
        when(expenses.sumBetween(userId, LocalDate.of(2026, 10, 1), FROM)).thenReturn(BigDecimal.ZERO);

        var byCategory = service.summarize(userId, NOVEMBER).byCategory();

        assertThat(byCategory).extracting(CategorySummary::categoryName).containsExactly("Top", "Beta", "Same", "Same");
        assertThat(byCategory.get(2).categoryId()).isEqualTo(low);
        assertThat(byCategory.get(3).categoryId()).isEqualTo(high);
    }

    private void stub(ExpenseCategoryTotal... rows) {
        when(expenses.sumByCategory(userId, FROM, TO)).thenReturn(List.of(rows));
        when(expenses.sumBetween(userId, LocalDate.of(2026, 10, 1), FROM)).thenReturn(BigDecimal.ZERO);
    }

    private static ExpenseCategoryTotal row(String name, String total, long count) {
        return new ExpenseCategoryTotal(UUID.randomUUID(), name, new BigDecimal(total), count);
    }
}
