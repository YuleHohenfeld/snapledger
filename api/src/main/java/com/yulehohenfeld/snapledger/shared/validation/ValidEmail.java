package com.yulehohenfeld.snapledger.shared.validation;

import java.lang.annotation.Documented;
import java.lang.annotation.ElementType;
import java.lang.annotation.Retention;
import java.lang.annotation.RetentionPolicy;
import java.lang.annotation.Target;

import jakarta.validation.Constraint;
import jakarta.validation.Payload;
import jakarta.validation.ReportAsSingleViolation;
import jakarta.validation.constraints.Email;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;

/**
 * The contract's email format, shared by register and login: a valid email, at most 254
 * characters, printable ASCII only and no whitespace anywhere ({@code " ana@x.com"} and
 * {@code "josé@x.com"} are rejected, never trimmed). Composed from standard constraints, so there
 * is no validator code of our own, and reported as one violation with one fixed message that never
 * contains the value. {@code null} is valid: combine with {@code @NotNull}. The empty string is
 * rejected by the pattern.
 *
 * <p>PT: O formato de email do contrato, compartilhado por cadastro e login: um email válido, no
 * máximo 254 caracteres, só ASCII imprimível e sem espaço em nenhuma posição
 * ({@code " ana@x.com"} e {@code "josé@x.com"} são rejeitados, nunca aparados). Composta de
 * constraints padrão, então não há código de validador nosso, e reportada como uma única violação
 * com uma mensagem fixa que nunca contém o valor. {@code null} é válido: combine com
 * {@code @NotNull}. A string vazia é rejeitada pelo pattern.
 */
@Documented
@Email
@Size(max = 254)
@Pattern(regexp = "[!-~]+") // printable ASCII 0x21-0x7E, so no space and no accent
// PT: ASCII imprimível 0x21-0x7E, então sem espaço e sem acento
@ReportAsSingleViolation
@Constraint(validatedBy = {})
@Target({ElementType.FIELD, ElementType.PARAMETER, ElementType.RECORD_COMPONENT, ElementType.TYPE_USE})
@Retention(RetentionPolicy.RUNTIME)
public @interface ValidEmail {

    String message() default "must be a valid email address: ASCII only, no spaces, at most 254 characters";

    Class<?>[] groups() default {};

    Class<? extends Payload>[] payload() default {};
}
