package com.yulehohenfeld.snapledger.shared.validation;

import java.lang.annotation.Documented;
import java.lang.annotation.ElementType;
import java.lang.annotation.Retention;
import java.lang.annotation.RetentionPolicy;
import java.lang.annotation.Target;

import jakarta.validation.Constraint;
import jakarta.validation.Payload;
import jakarta.validation.ReportAsSingleViolation;
import jakarta.validation.constraints.Pattern;

/**
 * The contract's account code format: exactly 6 ASCII digits. Full-width and other Unicode digits
 * are rejected, so what is hashed is always what was emailed. {@code null} is valid: combine with
 * {@code @NotNull}.
 *
 * <p>PT: O formato do código de conta do contrato: exatamente 6 dígitos ASCII. Dígitos de largura
 * total e outros dígitos Unicode são rejeitados, então o que vira hash é sempre o que foi enviado
 * por email. {@code null} é válido: combine com {@code @NotNull}.
 */
@Documented
@Pattern(regexp = "[0-9]{6}")
@ReportAsSingleViolation
@Constraint(validatedBy = {})
@Target({ElementType.FIELD, ElementType.PARAMETER, ElementType.RECORD_COMPONENT, ElementType.TYPE_USE})
@Retention(RetentionPolicy.RUNTIME)
public @interface ValidCode {

    String message() default "must be exactly 6 digits";

    Class<?>[] groups() default {};

    Class<? extends Payload>[] payload() default {};
}
