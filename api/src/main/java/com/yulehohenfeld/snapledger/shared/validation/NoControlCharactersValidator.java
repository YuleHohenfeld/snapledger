package com.yulehohenfeld.snapledger.shared.validation;

import jakarta.validation.ConstraintValidator;
import jakarta.validation.ConstraintValidatorContext;

/**
 * Walks code points, so a valid surrogate pair (an emoji) is one code point of a visible category
 * and only an unpaired surrogate shows up as category SURROGATE.
 *
 * <p>PT: Percorre code points, então um par de surrogates válido (um emoji) é um code point de uma
 * categoria visível, e só um surrogate sozinho aparece como categoria SURROGATE.
 */
public class NoControlCharactersValidator implements ConstraintValidator<NoControlCharacters, CharSequence> {

    @Override
    public boolean isValid(CharSequence value, ConstraintValidatorContext context) {
        return value == null || value.codePoints().noneMatch(NoControlCharactersValidator::isInvisible);
    }

    static boolean isInvisible(int codePoint) {
        var type = Character.getType(codePoint);
        return type == Character.CONTROL || type == Character.FORMAT || type == Character.SURROGATE;
    }
}
