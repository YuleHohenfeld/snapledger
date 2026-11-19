package com.yulehohenfeld.snapledger.shared.validation;

import java.lang.annotation.Documented;
import java.lang.annotation.ElementType;
import java.lang.annotation.Retention;
import java.lang.annotation.RetentionPolicy;
import java.lang.annotation.Target;

import jakarta.validation.Constraint;
import jakarta.validation.Payload;

/**
 * A {@code YearMonth} from 2000-01 to 9999-12 (four-digit years, so the text always has the
 * contract's {@code YYYY-MM} shape). {@code null} is valid (the parameter is required elsewhere).
 * The message never contains the value.
 *
 * <p>PT: Um {@code YearMonth} de 2000-01 a 9999-12 (anos de quatro dígitos, então o texto sempre
 * tem o formato {@code YYYY-MM} do contrato). {@code null} é válido (o parâmetro é obrigatório em
 * outro lugar). A mensagem nunca contém o valor.
 * Notes: docs/code-notes/expense.md#validmonth
 */
@Documented
@Constraint(validatedBy = ValidMonthValidator.class)
@Target({ElementType.FIELD, ElementType.PARAMETER, ElementType.RECORD_COMPONENT, ElementType.TYPE_USE})
@Retention(RetentionPolicy.RUNTIME)
public @interface ValidMonth {

    String message() default "must be a month between 2000-01 and 9999-12";

    Class<?>[] groups() default {};

    Class<? extends Payload>[] payload() default {};
}
