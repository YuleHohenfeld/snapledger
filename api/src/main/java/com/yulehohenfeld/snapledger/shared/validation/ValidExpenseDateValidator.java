package com.yulehohenfeld.snapledger.shared.validation;

import java.time.Clock;
import java.time.LocalDate;
import java.time.ZoneOffset;

import jakarta.validation.ConstraintValidator;
import jakarta.validation.ConstraintValidatorContext;

/**
 * Spring builds validators through {@code SpringConstraintValidatorFactory}, so the constructor
 * receives the application {@link Clock} and tests can fix "today".
 *
 * <p>PT: O Spring cria os validators pelo {@code SpringConstraintValidatorFactory}, então o
 * construtor recebe o {@link Clock} da aplicação e os testes podem fixar o "hoje".
 */
public class ValidExpenseDateValidator implements ConstraintValidator<ValidExpenseDate, LocalDate> {

    static final LocalDate OLDEST = LocalDate.of(2000, 1, 1);

    private final Clock clock;

    public ValidExpenseDateValidator(Clock clock) {
        this.clock = clock;
    }

    @Override
    public boolean isValid(LocalDate value, ConstraintValidatorContext context) {
        if (value == null) {
            return true;
        }
        var tomorrow = LocalDate.now(clock.withZone(ZoneOffset.UTC)).plusDays(1);
        return !value.isBefore(OLDEST) && !value.isAfter(tomorrow);
    }
}
