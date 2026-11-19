package com.yulehohenfeld.snapledger.shared.validation;

import java.util.regex.Pattern;

import jakarta.validation.ConstraintValidator;
import jakarta.validation.ConstraintValidatorContext;

/**
 * Full-match of the contract pattern, then "not zero" (a pattern cannot say "greater than 0").
 *
 * <p>PT: Casamento total com o padrão do contrato, depois "não é zero" (um padrão não diz "maior que 0").
 */
public class MoneyAmountValidator implements ConstraintValidator<MoneyAmount, CharSequence> {

    static final Pattern FORMAT = Pattern.compile("(0|[1-9][0-9]{0,9})(\\.[0-9]{1,2})?");

    @Override
    public boolean isValid(CharSequence value, ConstraintValidatorContext context) {
        if (value == null) {
            return true;
        }
        var text = value.toString();
        return FORMAT.matcher(text).matches() && text.chars().anyMatch(c -> c >= '1' && c <= '9');
    }
}
