package com.yulehohenfeld.snapledger.shared.validation;

import java.lang.annotation.Documented;
import java.lang.annotation.ElementType;
import java.lang.annotation.Retention;
import java.lang.annotation.RetentionPolicy;
import java.lang.annotation.Target;

import jakarta.validation.Constraint;
import jakarta.validation.Payload;

/**
 * An uppercase ISO 4217 code known to the JDK ({@code BRL}, {@code USD}...) that is real money:
 * precious metals, testing, unit-of-account and fund codes ({@code XAU}, {@code XTS}, {@code XDR},
 * {@code CLF}...) are rejected (contract). Not normalized: {@code brl} is rejected. {@code null} is
 * valid, so optional fields stay optional.
 *
 * <p>PT: Um código ISO 4217 em maiúsculas conhecido pelo JDK ({@code BRL}, {@code USD}...) que seja
 * dinheiro de verdade: códigos de metais preciosos, de teste, de unidades de conta e de fundos
 * ({@code XAU}, {@code XTS}, {@code XDR}, {@code CLF}...) são rejeitados (contrato). Não é
 * normalizado: {@code brl} é rejeitado. {@code null} é válido, então campos opcionais continuam
 * opcionais.
 */
@Documented
@Constraint(validatedBy = ValidCurrencyValidator.class)
@Target({ElementType.FIELD, ElementType.PARAMETER, ElementType.RECORD_COMPONENT, ElementType.TYPE_USE})
@Retention(RetentionPolicy.RUNTIME)
public @interface ValidCurrency {

    String message() default "must be an uppercase ISO 4217 currency code";

    Class<?>[] groups() default {};

    Class<? extends Payload>[] payload() default {};
}
