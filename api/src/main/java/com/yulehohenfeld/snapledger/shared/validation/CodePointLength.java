package com.yulehohenfeld.snapledger.shared.validation;

import java.lang.annotation.Documented;
import java.lang.annotation.ElementType;
import java.lang.annotation.Retention;
import java.lang.annotation.RetentionPolicy;
import java.lang.annotation.Target;

import jakarta.validation.Constraint;
import jakarta.validation.Payload;

/**
 * Length of a String in Unicode code points, the "characters" of the contract. {@code @Size}
 * counts Java chars (UTF-16 units), so an emoji counts as 2 and a name of 41 emoji would fail an
 * 80-character limit. PostgreSQL's {@code varchar(n)} counts code points too, so this limit and
 * the column agree exactly. A combined emoji such as a family (several code points joined) counts
 * as several. {@code null} is valid (combine with {@code @NotNull}/{@code @NotBlank}). The message
 * never contains the value.
 *
 * <p>PT: Tamanho de uma String em code points Unicode, os "caracteres" do contrato. O {@code @Size}
 * conta chars do Java (unidades UTF-16), então um emoji conta como 2 e um nome de 41 emojis
 * falharia num limite de 80 caracteres. O {@code varchar(n)} do PostgreSQL também conta code
 * points, então este limite e a coluna concordam exatamente. Um emoji combinado como uma família
 * (vários code points unidos) conta como vários. {@code null} é válido (combine com
 * {@code @NotNull}/{@code @NotBlank}). A mensagem nunca contém o valor.
 */
@Documented
@Constraint(validatedBy = CodePointLengthValidator.class)
@Target({ElementType.FIELD, ElementType.PARAMETER, ElementType.RECORD_COMPONENT, ElementType.TYPE_USE})
@Retention(RetentionPolicy.RUNTIME)
public @interface CodePointLength {

    String message() default "must be between {min} and {max} characters";

    int min() default 0;

    int max();

    Class<?>[] groups() default {};

    Class<? extends Payload>[] payload() default {};
}
