package com.yulehohenfeld.snapledger.expense.repository;

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

    /** One atomic statement; returns the rows deleted (0 = not found or not the user's).
     *  PT: Um comando atômico; devolve as linhas apagadas (0 = não existe ou não é do usuário). */
    @Modifying(flushAutomatically = true, clearAutomatically = true)
    @Query("delete from Expense e where e.id = :id and e.userId = :userId")
    int deleteByIdAndUserId(UUID id, UUID userId);
}
