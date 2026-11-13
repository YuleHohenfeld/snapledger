package com.yulehohenfeld.snapledger.shared.validation;

import java.lang.annotation.Documented;
import java.lang.annotation.ElementType;
import java.lang.annotation.Retention;
import java.lang.annotation.RetentionPolicy;
import java.lang.annotation.Target;

import jakarta.validation.Constraint;
import jakarta.validation.Payload;

/**
 * Display text without invisible characters: rejects Unicode control characters (category Cc:
 * NUL, tab, newline, escape...), format characters (Cf: zero-width space, right-to-left override,
 * byte order mark...) and unpaired surrogates (Cs, which no encoding can store). These are used to
 * fake names that look empty or identical to someone else's, to reverse text on screen, or to
 * break logs and the database (PostgreSQL refuses NUL with an error, not a 400). {@code null} is
 * valid. The message never contains the value.
 *
 * <p>PT: Texto de exibição sem caracteres invisíveis: rejeita caracteres de controle Unicode
 * (categoria Cc: NUL, tab, quebra de linha, escape...), de formatação (Cf: espaço de largura zero,
 * inversão direita-para-esquerda, marca de ordem de bytes...) e surrogates sozinhos (Cs, que
 * nenhuma codificação consegue gravar). Eles são usados para forjar nomes que parecem vazios ou
 * idênticos aos de outra pessoa, para inverter texto na tela, ou para quebrar logs e o banco (o
 * PostgreSQL recusa NUL com um erro, não com um 400). {@code null} é válido. A mensagem nunca
 * contém o valor.
 */
@Documented
@Constraint(validatedBy = NoControlCharactersValidator.class)
@Target({ElementType.FIELD, ElementType.PARAMETER, ElementType.RECORD_COMPONENT, ElementType.TYPE_USE})
@Retention(RetentionPolicy.RUNTIME)
public @interface NoControlCharacters {

    String message() default "must not contain control or invisible formatting characters";

    Class<?>[] groups() default {};

    Class<? extends Payload>[] payload() default {};
}
