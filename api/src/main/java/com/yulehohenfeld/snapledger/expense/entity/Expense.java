package com.yulehohenfeld.snapledger.expense.entity;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.time.Instant;
import java.time.LocalDate;
import java.time.temporal.ChronoUnit;
import java.util.UUID;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.FetchType;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.Table;

import lombok.AccessLevel;
import lombok.Getter;
import lombok.NoArgsConstructor;

import com.yulehohenfeld.snapledger.category.entity.Category;
import com.yulehohenfeld.snapledger.shared.persistence.AssignedIdEntity;

/** An expense of one user; built by {@link #create}, changed by {@link #update}.
 *  PT: Uma despesa de um usuário; criada pelo {@link #create}, alterada pelo {@link #update}.
 *  Notes: docs/code-notes/expense.md#expense */
@Entity
@Table(name = "expenses")
@Getter
@NoArgsConstructor(access = AccessLevel.PROTECTED) // JPA only
// PT: só para o JPA
public class Expense extends AssignedIdEntity {

    @Column(name = "user_id", nullable = false, updatable = false)
    private UUID userId;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "category_id", nullable = false)
    private Category category;

    @Column(nullable = false, precision = 12, scale = 2)
    private BigDecimal amount;

    @Column(nullable = false, length = 120)
    private String description;

    @Column(name = "expense_date", nullable = false)
    private LocalDate expenseDate;

    @Column(name = "created_at", nullable = false, updatable = false)
    private Instant createdAt;

    @Column(name = "updated_at", nullable = false)
    private Instant updatedAt;

    private Expense(UUID id) {
        super(id);
    }

    /** A new expense; the caller has already validated the values and checked the category belongs to the user.
     *  PT: Uma despesa nova; quem chama já validou os valores e conferiu que a categoria é do usuário. */
    public static Expense create(UUID userId, Category category, BigDecimal amount, String description,
                                 LocalDate date, Instant now) {
        var expense = new Expense(UUID.randomUUID());
        expense.userId = userId;
        expense.createdAt = now.truncatedTo(ChronoUnit.MICROS);
        expense.apply(category, amount, description, date, expense.createdAt);
        return expense;
    }

    /** Replaces every editable field (PUT). PT: Substitui todos os campos editáveis (PUT).
     *  Notes: docs/code-notes/expense.md#update */
    public void update(Category category, BigDecimal amount, String description, LocalDate date, Instant now) {
        var instant = now.truncatedTo(ChronoUnit.MICROS);
        apply(category, amount, description, date, instant.isBefore(createdAt) ? createdAt : instant);
    }

    private void apply(Category category, BigDecimal amount, String description, LocalDate date, Instant now) {
        this.category = category;
        this.amount = amount.setScale(2, RoundingMode.UNNECESSARY); // validated before; never rounds
        this.description = description.strip();
        this.expenseDate = date;
        this.updatedAt = now;
    }

    // Only the id: amount and description are personal financial data and never reach a log.
    // PT: Só o id: valor e descrição são dados financeiros pessoais e nunca chegam a um log.
    @Override
    public String toString() {
        return "Expense[id=" + getId() + "]";
    }
}
