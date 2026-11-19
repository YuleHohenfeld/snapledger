package com.yulehohenfeld.snapledger.expense.dto;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.UUID;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;

import com.fasterxml.jackson.annotation.JsonIgnore;

import com.yulehohenfeld.snapledger.shared.validation.CodePointLength;
import com.yulehohenfeld.snapledger.shared.validation.MoneyAmount;
import com.yulehohenfeld.snapledger.shared.validation.NoControlCharacters;
import com.yulehohenfeld.snapledger.shared.validation.ValidExpenseDate;

/** Body of POST and PUT /expenses; the amount is text so it is never rounded by a double.
 *  PT: Corpo do POST e do PUT /expenses; o valor é texto para nunca passar por um double.
 *  Notes: docs/code-notes/expense.md#expenserequest */
public record ExpenseRequest(
        @NotNull @MoneyAmount String amount,
        @NotBlank @CodePointLength(min = 1, max = 120) @NoControlCharacters String description,
        @NotNull @ValidExpenseDate LocalDate date,
        @NotNull UUID categoryId) {

    public ExpenseRequest {
        description = description == null ? null : description.strip();
    }

    /** The validated amount with scale 2; call only after validation. PT: O valor validado com escala 2; só depois da validação. */
    @JsonIgnore
    public BigDecimal amountValue() {
        return new BigDecimal(amount).setScale(2);
    }

    // Amount and description are personal financial data: logs carry ids only.
    // PT: Valor e descrição são dados financeiros pessoais: os logs levam só ids.
    @Override
    public String toString() {
        return "ExpenseRequest[amount=****, description=****, date=" + date + ", categoryId=" + categoryId + "]";
    }
}
