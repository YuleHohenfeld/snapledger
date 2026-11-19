package com.yulehohenfeld.snapledger.expense.service;

import java.time.Clock;
import java.time.YearMonth;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import lombok.RequiredArgsConstructor;

import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.orm.ObjectOptimisticLockingFailureException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import com.yulehohenfeld.snapledger.category.service.CategoryService;
import com.yulehohenfeld.snapledger.expense.dto.ExpenseRequest;
import com.yulehohenfeld.snapledger.expense.dto.ExpenseResponse;
import com.yulehohenfeld.snapledger.expense.entity.Expense;
import com.yulehohenfeld.snapledger.expense.mapper.ExpenseMapper;
import com.yulehohenfeld.snapledger.expense.repository.ExpenseRepository;
import com.yulehohenfeld.snapledger.shared.error.ConstraintViolations;
import com.yulehohenfeld.snapledger.shared.error.NotFoundException;

/**
 * Expenses of one user; every method takes the user id, so the AI tools of Phase 3b can call it.
 *
 * <p>PT: Despesas de um usuário; todo método recebe o id do usuário, então as tools de IA da Fase 3b podem chamá-lo.
 * Notes: docs/code-notes/expense.md#expenseservice
 */
@Service
@RequiredArgsConstructor
public class ExpenseService {

    static final String CATEGORY_CONSTRAINT = "fk_expenses_categories";

    private final ExpenseRepository expenses;
    private final CategoryService categories;
    private final ExpenseMapper mapper;
    private final Clock clock;

    /** The month's expenses, newest first; a category filter the user cannot see is 404.
     *  PT: As despesas do mês, mais novas primeiro; um filtro de categoria que o usuário não vê é 404. */
    @Transactional(readOnly = true)
    public List<ExpenseResponse> list(UUID userId, YearMonth month, Optional<UUID> categoryId) {
        var from = month.atDay(1);
        var to = month.atEndOfMonth();
        var found = categoryId.isPresent()
                ? expenses.findMonthInCategory(userId, from, to, categories.requireVisible(userId, categoryId.get()).getId())
                : expenses.findMonth(userId, from, to);
        return found.stream().map(mapper::toResponse).toList();
    }

    @Transactional(readOnly = true)
    public ExpenseResponse get(UUID userId, UUID id) {
        return mapper.toResponse(expenses.findByIdAndUserId(id, userId).orElseThrow(NotFoundException::new));
    }

    /**
     * Inserts the expense now; a category that is not visible, or deleted meanwhile, is 404.
     *
     * <p>PT: Insere a despesa agora; uma categoria não visível, ou apagada nesse meio tempo, é 404.
     * Notes: docs/code-notes/expense.md#create
     */
    @Transactional
    public ExpenseResponse create(UUID userId, ExpenseRequest request) {
        var category = categories.requireVisible(userId, request.categoryId());
        var expense = Expense.create(userId, category, request.amountValue(), request.description(),
                request.date(), clock.instant());
        try {
            expenses.saveAndFlush(expense);
        } catch (DataIntegrityViolationException e) {
            throw categoryGoneOrRethrow(e);
        }
        return mapper.toResponse(expense);
    }

    /** Full replacement (PUT); another user's expense or category is 404. PT: Substituição total (PUT); despesa ou categoria de outro usuário é 404. */
    @Transactional
    public ExpenseResponse replace(UUID userId, UUID id, ExpenseRequest request) {
        var expense = expenses.findByIdAndUserId(id, userId).orElseThrow(NotFoundException::new);
        var category = categories.requireVisible(userId, request.categoryId());
        expense.update(category, request.amountValue(), request.description(), request.date(), clock.instant());
        try {
            expenses.flush();
        } catch (DataIntegrityViolationException e) {
            throw categoryGoneOrRethrow(e);
        } catch (ObjectOptimisticLockingFailureException e) {
            // No @Version: 0 rows updated means the expense was deleted after we loaded it. PT: Sem @Version: 0 linhas = despesa apagada depois de carregada.
            throw new NotFoundException();
        }
        return mapper.toResponse(expense);
    }

    /** One atomic scoped delete; 0 rows (missing or another user's) is 404. PT: Um delete atômico com escopo; 0 linhas (inexistente ou de outro usuário) é 404. */
    @Transactional
    public void delete(UUID userId, UUID id) {
        if (expenses.deleteByIdAndUserId(id, userId) == 0) {
            throw new NotFoundException();
        }
    }

    private static RuntimeException categoryGoneOrRethrow(DataIntegrityViolationException e) {
        return ConstraintViolations.violates(e, CATEGORY_CONSTRAINT) ? new NotFoundException() : e;
    }
}
