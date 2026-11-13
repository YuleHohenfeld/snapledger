package com.yulehohenfeld.snapledger.shared.validation;

import java.lang.annotation.Documented;
import java.lang.annotation.ElementType;
import java.lang.annotation.Retention;
import java.lang.annotation.RetentionPolicy;
import java.lang.annotation.Target;

import jakarta.validation.Constraint;
import jakarta.validation.Payload;

/**
 * Length of a String in UTF-8 bytes, not in characters. {@code @Size} counts Java chars (UTF-16
 * units), but bcrypt reads at most 72 <b>bytes</b>: "é" is 1 char and 2 bytes, so a password of 72
 * chars can be 144 bytes and bcrypt would silently ignore the second half. Text with an unpaired
 * surrogate is rejected too (it has no UTF-8 form). {@code null} is valid (combine with
 * {@code @NotNull}/{@code @NotBlank}). The message never contains the value.
 *
 * <p>PT: Tamanho de uma String em bytes UTF-8, não em caracteres. O {@code @Size} conta chars do
 * Java (unidades UTF-16), mas o bcrypt lê no máximo 72 <b>bytes</b>: "é" é 1 char e 2 bytes, então
 * uma senha de 72 chars pode ter 144 bytes e o bcrypt ignoraria a segunda metade sem avisar. Texto
 * com um surrogate sozinho também é rejeitado (ele não tem forma UTF-8). {@code null} é válido (combine com {@code @NotNull}/{@code @NotBlank}). A mensagem nunca contém o
 * valor.
 */
@Documented
@Constraint(validatedBy = Utf8ByteSizeValidator.class)
@Target({ElementType.FIELD, ElementType.PARAMETER, ElementType.RECORD_COMPONENT, ElementType.TYPE_USE})
@Retention(RetentionPolicy.RUNTIME)
public @interface Utf8ByteSize {

    String message() default "must be between {min} and {max} bytes in UTF-8";

    int min() default 0;

    int max();

    Class<?>[] groups() default {};

    Class<? extends Payload>[] payload() default {};
}
