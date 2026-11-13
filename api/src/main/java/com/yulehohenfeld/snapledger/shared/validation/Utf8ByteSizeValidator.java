package com.yulehohenfeld.snapledger.shared.validation;

import java.nio.charset.StandardCharsets;

import jakarta.validation.ConstraintValidator;
import jakarta.validation.ConstraintValidatorContext;

/**
 * Counts bytes with the same encoding call the password encoder uses ({@code getBytes(UTF_8)}),
 * so the limit checked here is exactly what bcrypt receives. An unpaired surrogate is rejected
 * first: {@code getBytes} would silently replace it with "?", so "pass\ud800word" and
 * "pass\udbffword" would become the same password.
 *
 * <p>PT: Conta bytes com a mesma chamada de codificação que o encoder de senha usa
 * ({@code getBytes(UTF_8)}), então o limite conferido aqui é exatamente o que o bcrypt recebe. Um
 * surrogate sozinho é rejeitado antes: o {@code getBytes} o trocaria por "?" sem avisar, então
 * "pass\ud800word" e "pass\udbffword" virariam a mesma senha.
 */
public class Utf8ByteSizeValidator implements ConstraintValidator<Utf8ByteSize, CharSequence> {

    static final String INVALID_TEXT_MESSAGE = "must be valid Unicode text";

    private int min;
    private int max;

    @Override
    public void initialize(Utf8ByteSize annotation) {
        if (annotation.min() < 0 || annotation.max() < annotation.min()) {
            throw new IllegalArgumentException("@Utf8ByteSize needs 0 <= min <= max");
        }
        this.min = annotation.min();
        this.max = annotation.max();
    }

    @Override
    public boolean isValid(CharSequence value, ConstraintValidatorContext context) {
        if (value == null) {
            return true;
        }
        if (value.codePoints().anyMatch(codePoint -> Character.getType(codePoint) == Character.SURROGATE)) {
            // A fixed message of its own: "between 8 and 72 bytes" would be misleading here.
            // PT: Uma mensagem fixa própria: "entre 8 e 72 bytes" enganaria aqui.
            context.disableDefaultConstraintViolation();
            context.buildConstraintViolationWithTemplate(INVALID_TEXT_MESSAGE).addConstraintViolation();
            return false;
        }
        var bytes = value.toString().getBytes(StandardCharsets.UTF_8).length;
        return bytes >= min && bytes <= max;
    }
}
