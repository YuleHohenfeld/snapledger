package com.yulehohenfeld.snapledger.expense.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

import java.math.BigDecimal;
import java.time.Clock;
import java.time.Instant;
import java.time.LocalDate;
import java.time.YearMonth;
import java.time.ZoneOffset;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.orm.ObjectOptimisticLockingFailureException;

import com.yulehohenfeld.snapledger.category.entity.Category;
import com.yulehohenfeld.snapledger.category.mapper.CategoryMapperImpl;
import com.yulehohenfeld.snapledger.category.service.CategoryService;
import com.yulehohenfeld.snapledger.expense.dto.ExpenseRequest;
import com.yulehohenfeld.snapledger.expense.entity.Expense;
import com.yulehohenfeld.snapledger.expense.mapper.ExpenseMapperImpl;
import com.yulehohenfeld.snapledger.expense.repository.ExpenseRepository;
import com.yulehohenfeld.snapledger.shared.error.NotFoundException;
import com.yulehohenfeld.snapledger.support.TestConstraintViolations;

/**
 * Expense rules with the repository and the category service mocked.
 *
 * <p>PT: Regras de despesa com o repository e o service de categorias simulados.
 */
@ExtendWith(MockitoExtension.class)
class ExpenseServiceTest {

    static final Instant NOW = Instant.parse("2026-11-12T10:00:00Z");
    static final LocalDate TODAY = LocalDate.of(2026, 11, 12);

    @Mock
    ExpenseRepository expenses;

    @Mock
    CategoryService categories;

    ExpenseService service;

    final UUID userId = UUID.randomUUID();
    Category category;

    @BeforeEach
    void createService() {
        service = new ExpenseService(expenses, categories, new ExpenseMapperImpl(new CategoryMapperImpl()),
                Clock.fixed(NOW, ZoneOffset.UTC));
        category = Category.createOwn(userId, "Pets", NOW);
    }

    @Test
    void listWithoutFilterAsksForTheWholeMonthIncludingItsLastDay() {
        var expense = Expense.create(userId, category, new BigDecimal("12.5"), "Lunch", TODAY, NOW);
        when(expenses.findMonth(userId, LocalDate.of(2026, 2, 1), LocalDate.of(2026, 2, 28))).thenReturn(List.of(expense));

        var result = service.list(userId, YearMonth.of(2026, 2), Optional.empty());

        assertThat(result).singleElement().satisfies(r -> {
            assertThat(r.amount()).isEqualTo(new BigDecimal("12.50"));
            assertThat(r.date()).isEqualTo(TODAY);
            assertThat(r.category().name()).isEqualTo("Pets");
        });
        verifyNoInteractions(categories);
    }

    @Test
    void listWithAFilterChecksTheCategoryIsVisibleFirst() {
        when(categories.requireVisible(userId, category.getId())).thenReturn(category);
        when(expenses.findMonthInCategory(userId, LocalDate.of(2024, 2, 1), LocalDate.of(2024, 2, 29), category.getId()))
                .thenReturn(List.of());

        assertThat(service.list(userId, YearMonth.of(2024, 2), Optional.of(category.getId()))).isEmpty();
    }

    @Test
    void listWithAFilterOfAnInvisibleCategoryIsNotFoundAndQueriesNothing() {
        var other = UUID.randomUUID();
        when(categories.requireVisible(userId, other)).thenThrow(new NotFoundException());

        assertThatThrownBy(() -> service.list(userId, YearMonth.of(2026, 11), Optional.of(other)))
                .isInstanceOf(NotFoundException.class);

        verify(expenses, never()).findMonthInCategory(any(), any(), any(), any());
    }

    @Test
    void getIsScopedByTheUserAndNotFoundOtherwise() {
        var id = UUID.randomUUID();
        when(expenses.findByIdAndUserId(id, userId)).thenReturn(Optional.empty());

        assertThatThrownBy(() -> service.get(userId, id)).isInstanceOf(NotFoundException.class);
    }

    @Test
    void createStoresTheExactAmountWithScale2AndTheClockInstant() {
        when(categories.requireVisible(userId, category.getId())).thenReturn(category);

        var result = service.create(userId, request("12.5", "  Lunch ", category.getId()));

        var saved = ArgumentCaptor.forClass(Expense.class);
        verify(expenses).saveAndFlush(saved.capture());
        assertThat(saved.getValue().getUserId()).isEqualTo(userId);
        assertThat(saved.getValue().getAmount()).isEqualTo(new BigDecimal("12.50"));
        assertThat(saved.getValue().getDescription()).isEqualTo("Lunch");
        assertThat(saved.getValue().getCreatedAt()).isEqualTo(NOW);
        assertThat(saved.getValue().getUpdatedAt()).isEqualTo(NOW);
        assertThat(result.amount().toString()).isEqualTo("12.50");
    }

    @Test
    void createWithAnInvisibleCategoryIsNotFoundAndInsertsNothing() {
        var other = UUID.randomUUID();
        when(categories.requireVisible(userId, other)).thenThrow(new NotFoundException());

        assertThatThrownBy(() -> service.create(userId, request("1", "x", other))).isInstanceOf(NotFoundException.class);

        verify(expenses, never()).saveAndFlush(any());
    }

    @Test
    void createWhenTheCategoryWasDeletedMeanwhileIsNotFound() {
        when(categories.requireVisible(userId, category.getId())).thenReturn(category);
        when(expenses.saveAndFlush(any())).thenThrow(TestConstraintViolations.translated("fk_expenses_categories"));

        assertThatThrownBy(() -> service.create(userId, request("1", "x", category.getId())))
                .isInstanceOf(NotFoundException.class);
    }

    @Test
    void createDoesNotHideOtherIntegrityViolations() {
        var other = TestConstraintViolations.translated("ck_expenses_amount_positive");
        when(categories.requireVisible(userId, category.getId())).thenReturn(category);
        when(expenses.saveAndFlush(any())).thenThrow(other);

        assertThatThrownBy(() -> service.create(userId, request("1", "x", category.getId()))).isSameAs(other);
    }

    @Test
    void replaceChangesEveryFieldAndMovesUpdatedAtButNotCreatedAt() {
        var existing = Expense.create(userId, category, new BigDecimal("1.00"), "Old", TODAY.minusDays(3), NOW.minusSeconds(100));
        var newCategory = Category.createOwn(userId, "Gym", NOW);
        when(expenses.findByIdAndUserId(existing.getId(), userId)).thenReturn(Optional.of(existing));
        when(categories.requireVisible(userId, newCategory.getId())).thenReturn(newCategory);

        var result = service.replace(userId, existing.getId(), request("99.99", "New", newCategory.getId()));

        assertThat(existing.getAmount()).isEqualTo(new BigDecimal("99.99"));
        assertThat(existing.getDescription()).isEqualTo("New");
        assertThat(existing.getCategory()).isSameAs(newCategory);
        assertThat(existing.getCreatedAt()).isEqualTo(NOW.minusSeconds(100));
        assertThat(existing.getUpdatedAt()).isEqualTo(NOW);
        assertThat(result.category().name()).isEqualTo("Gym");
        verify(expenses).flush();
    }

    @Test
    void replaceOfAnExpenseTheUserDoesNotOwnIsNotFoundAndChecksNoCategory() {
        var id = UUID.randomUUID();
        when(expenses.findByIdAndUserId(id, userId)).thenReturn(Optional.empty());

        assertThatThrownBy(() -> service.replace(userId, id, request("1", "x", category.getId())))
                .isInstanceOf(NotFoundException.class);

        verifyNoInteractions(categories);
    }

    @Test
    void replaceWithAnInvisibleCategoryIsNotFoundAndKeepsTheExpenseUntouched() {
        var existing = Expense.create(userId, category, new BigDecimal("1.00"), "Old", TODAY, NOW);
        var other = UUID.randomUUID();
        when(expenses.findByIdAndUserId(existing.getId(), userId)).thenReturn(Optional.of(existing));
        when(categories.requireVisible(userId, other)).thenThrow(new NotFoundException());

        assertThatThrownBy(() -> service.replace(userId, existing.getId(), request("5", "New", other)))
                .isInstanceOf(NotFoundException.class);

        assertThat(existing.getDescription()).isEqualTo("Old");
    }

    @Test
    void replaceWhenTheCategoryWasDeletedMeanwhileIsNotFound() {
        var existing = Expense.create(userId, category, new BigDecimal("1.00"), "Old", TODAY, NOW);
        when(expenses.findByIdAndUserId(existing.getId(), userId)).thenReturn(Optional.of(existing));
        when(categories.requireVisible(userId, category.getId())).thenReturn(category);
        doThrow(TestConstraintViolations.translated("fk_expenses_categories")).when(expenses).flush();

        assertThatThrownBy(() -> service.replace(userId, existing.getId(), request("5", "New", category.getId())))
                .isInstanceOf(NotFoundException.class);
    }

    @Test
    void replaceOfAnExpenseDeletedMeanwhileIsNotFound() {
        var existing = Expense.create(userId, category, new BigDecimal("1.00"), "Old", TODAY, NOW);
        when(expenses.findByIdAndUserId(existing.getId(), userId)).thenReturn(Optional.of(existing));
        when(categories.requireVisible(userId, category.getId())).thenReturn(category);
        doThrow(new ObjectOptimisticLockingFailureException(Expense.class, existing.getId())).when(expenses).flush();

        assertThatThrownBy(() -> service.replace(userId, existing.getId(), request("5", "New", category.getId())))
                .isInstanceOf(NotFoundException.class);
    }

    @Test
    void replaceNeverMovesUpdatedAtBeforeCreatedAtWhenTheClockWentBackwards() {
        var existing = Expense.create(userId, category, new BigDecimal("1.00"), "Old", TODAY, NOW.plusSeconds(60));
        when(expenses.findByIdAndUserId(existing.getId(), userId)).thenReturn(Optional.of(existing));
        when(categories.requireVisible(userId, category.getId())).thenReturn(category);

        service.replace(userId, existing.getId(), request("5", "New", category.getId()));

        assertThat(existing.getUpdatedAt()).isEqualTo(existing.getCreatedAt());
    }

    @Test
    void deleteWithNoRowAffectedIsNotFound() {
        var id = UUID.randomUUID();
        when(expenses.deleteByIdAndUserId(id, userId)).thenReturn(0);

        assertThatThrownBy(() -> service.delete(userId, id)).isInstanceOf(NotFoundException.class);
    }

    @Test
    void deleteWithOneRowAffectedSucceeds() {
        var id = UUID.randomUUID();
        when(expenses.deleteByIdAndUserId(id, userId)).thenReturn(1);

        service.delete(userId, id);

        verify(expenses).deleteByIdAndUserId(id, userId);
    }

    @Test
    void anIntegrityErrorUnrelatedToTheCategoryIsNotTurnedIntoNotFoundOnReplace() {
        var existing = Expense.create(userId, category, new BigDecimal("1.00"), "Old", TODAY, NOW);
        when(expenses.findByIdAndUserId(existing.getId(), userId)).thenReturn(Optional.of(existing));
        when(categories.requireVisible(userId, category.getId())).thenReturn(category);
        doThrow(new DataIntegrityViolationException("other")).when(expenses).flush();

        assertThatThrownBy(() -> service.replace(userId, existing.getId(), request("5", "New", category.getId())))
                .isInstanceOf(DataIntegrityViolationException.class);
    }

    private static ExpenseRequest request(String amount, String description, UUID categoryId) {
        return new ExpenseRequest(amount, description, TODAY, categoryId);
    }
}
