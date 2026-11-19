package com.yulehohenfeld.snapledger.shared.validation;

import java.time.YearMonth;

import jakarta.validation.ConstraintValidator;
import jakarta.validation.ConstraintValidatorContext;

/**
 * Range check on an already parsed month.
 *
 * <p>PT: Checagem de faixa num mês já convertido.
 */
public class ValidMonthValidator implements ConstraintValidator<ValidMonth, YearMonth> {

    static final YearMonth FIRST = YearMonth.of(2000, 1);
    static final YearMonth LAST = YearMonth.of(9999, 12);

    @Override
    public boolean isValid(YearMonth value, ConstraintValidatorContext context) {
        return value == null || (!value.isBefore(FIRST) && !value.isAfter(LAST));
    }
}
