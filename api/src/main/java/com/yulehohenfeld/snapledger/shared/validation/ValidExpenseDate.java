package com.yulehohenfeld.snapledger.shared.validation;

import java.lang.annotation.Documented;
import java.lang.annotation.ElementType;
import java.lang.annotation.Retention;
import java.lang.annotation.RetentionPolicy;
import java.lang.annotation.Target;

import jakarta.validation.Constraint;
import jakarta.validation.Payload;

/**
 * An expense date from 2000-01-01 up to tomorrow in UTC (server clock; tolerates timezone
 * differences). {@code null} is valid (combine with {@code @NotNull}). The message never contains
 * the value.
 *
 * <p>PT: Uma data de despesa de 2000-01-01 até amanhã em UTC (relógio do servidor; tolera
 * diferenças de fuso). {@code null} é válido (combine com {@code @NotNull}). A mensagem nunca
 * contém o valor.
 * Notes: docs/code-notes/expense.md#validexpensedate
 */
@Documented
@Constraint(validatedBy = ValidExpenseDateValidator.class)
@Target({ElementType.FIELD, ElementType.PARAMETER, ElementType.RECORD_COMPONENT, ElementType.TYPE_USE})
@Retention(RetentionPolicy.RUNTIME)
public @interface ValidExpenseDate {

    String message() default "must be between 2000-01-01 and tomorrow";

    Class<?>[] groups() default {};

    Class<? extends Payload>[] payload() default {};
}
