package com.yulehohenfeld.snapledger.expense.repository;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;

import com.yulehohenfeld.snapledger.expense.entity.Expense;

/** Every method takes the user id: ownership lives in the query. PT: Todo método recebe o id do usuário: a posse está na query.
 *  Notes: docs/code-notes/expense.md#expenserepository */
public interface ExpenseRepository extends JpaRepository<Expense, UUID> {

    @Query("select e from Expense e join fetch e.category where e.id = :id and e.userId = :userId")
    Optional<Expense> findByIdAndUserId(UUID id, UUID userId);

    /** Both bounds are inclusive (first and last day of the month); newest first, ties by createdAt then id.
     *  PT: Os dois limites são inclusivos (primeiro e último dia do mês); mais novas primeiro, empate por createdAt e id. */
    @Query("""
            select e from Expense e join fetch e.category
            where e.userId = :userId and e.expenseDate >= :from and e.expenseDate <= :to
            order by e.expenseDate desc, e.createdAt desc, e.id desc
            """)
    List<Expense> findMonth(UUID userId, LocalDate from, LocalDate to);

    @Query("""
            select e from Expense e join fetch e.category
            where e.userId = :userId and e.expenseDate >= :from and e.expenseDate <= :to
              and e.category.id = :categoryId
            order by e.expenseDate desc, e.createdAt desc, e.id desc
            """)
    List<Expense> findMonthInCategory(UUID userId, LocalDate from, LocalDate to, UUID categoryId);

    /** Sum and count per category in [from, to): half-open, the column has no function around it, so
     *  idx_expenses_user_date serves it. The sum is done by PostgreSQL on numeric (exact).
     *  PT: Soma e contagem por categoria em [from, to): intervalo semiaberto, sem função na coluna, então o
     *  idx_expenses_user_date atende. A soma é feita pelo PostgreSQL em numeric (exata).
     *  Notes: docs/code-notes/expense.md#summary-query */
    @Query("""
            select new com.yulehohenfeld.snapledger.expense.repository.ExpenseCategoryTotal(
                c.id, c.name, sum(e.amount), count(e))
            from Expense e join e.category c
            where e.userId = :userId and e.expenseDate >= :from and e.expenseDate < :to
            group by c.id, c.name
            """)
    List<ExpenseCategoryTotal> sumByCategory(UUID userId, LocalDate from, LocalDate to);

    /** Total in [from, to), 0 when there is none. PT: Total em [from, to), 0 quando não há nenhum. */
    @Query("""
            select coalesce(sum(e.amount), 0) from Expense e
            where e.userId = :userId and e.expenseDate >= :from and e.expenseDate < :to
            """)
    BigDecimal sumBetween(UUID userId, LocalDate from, LocalDate to);

    /** One atomic statement; returns the rows deleted (0 = not found or not the user's).
     *  PT: Um comando atômico; devolve as linhas apagadas (0 = não existe ou não é do usuário). */
    @Modifying(flushAutomatically = true, clearAutomatically = true)
    @Query("delete from Expense e where e.id = :id and e.userId = :userId")
    int deleteByIdAndUserId(UUID id, UUID userId);
}
