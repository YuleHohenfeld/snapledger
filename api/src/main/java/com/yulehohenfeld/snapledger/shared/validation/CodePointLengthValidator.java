package com.yulehohenfeld.snapledger.shared.validation;

import jakarta.validation.ConstraintValidator;
import jakarta.validation.ConstraintValidatorContext;

/**
 * Counts with {@code codePointCount}: a surrogate pair is one code point, as in PostgreSQL. An
 * unpaired surrogate counts as one; rejecting it is the job of {@link NoControlCharacters}.
 *
 * <p>PT: Conta com {@code codePointCount}: um par de surrogates é um code point, como no
 * PostgreSQL. Um surrogate sozinho conta como um; rejeitá-lo é trabalho do
 * {@link NoControlCharacters}.
 */
public class CodePointLengthValidator implements ConstraintValidator<CodePointLength, CharSequence> {

    private int min;
    private int max;

    @Override
    public void initialize(CodePointLength annotation) {
        if (annotation.min() < 0 || annotation.max() < annotation.min()) {
            throw new IllegalArgumentException("@CodePointLength needs 0 <= min <= max");
        }
        this.min = annotation.min();
        this.max = annotation.max();
    }

    @Override
    public boolean isValid(CharSequence value, ConstraintValidatorContext context) {
        if (value == null) {
            return true;
        }
        var length = Character.codePointCount(value, 0, value.length());
        return length >= min && length <= max;
    }
}
