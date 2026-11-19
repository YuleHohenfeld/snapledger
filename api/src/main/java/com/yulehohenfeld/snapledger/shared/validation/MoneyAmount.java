package com.yulehohenfeld.snapledger.shared.validation;

import java.lang.annotation.Documented;
import java.lang.annotation.ElementType;
import java.lang.annotation.Retention;
import java.lang.annotation.RetentionPolicy;
import java.lang.annotation.Target;

import jakarta.validation.Constraint;
import jakarta.validation.Payload;

/**
 * A money amount written as text: plain ASCII digits, at most 10 integer digits without leading
 * zeros, an optional point with 1 or 2 decimals, greater than zero (so at most 9999999999.99).
 * Never rounded: a third decimal is rejected. {@code null} is valid (combine with
 * {@code @NotNull}). The message never contains the value.
 *
 * <p>PT: Um valor em dinheiro escrito como texto: só dígitos ASCII, no máximo 10 dígitos inteiros
 * sem zeros à esquerda, um ponto opcional com 1 ou 2 decimais, maior que zero (então no máximo
 * 9999999999.99). Nunca arredondado: uma terceira casa decimal é rejeitada. {@code null} é válido
 * (combine com {@code @NotNull}). A mensagem nunca contém o valor.
 * Notes: docs/code-notes/expense.md#moneyamount
 */
@Documented
@Constraint(validatedBy = MoneyAmountValidator.class)
@Target({ElementType.FIELD, ElementType.PARAMETER, ElementType.RECORD_COMPONENT, ElementType.TYPE_USE})
@Retention(RetentionPolicy.RUNTIME)
public @interface MoneyAmount {

    String message() default "must be a positive amount with at most two decimal places and at most ten integer digits";

    Class<?>[] groups() default {};

    Class<? extends Payload>[] payload() default {};
}
