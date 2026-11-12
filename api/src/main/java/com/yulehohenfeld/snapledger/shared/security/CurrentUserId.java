package com.yulehohenfeld.snapledger.shared.security;

import java.lang.annotation.Documented;
import java.lang.annotation.ElementType;
import java.lang.annotation.Retention;
import java.lang.annotation.RetentionPolicy;
import java.lang.annotation.Target;

import org.springframework.security.core.annotation.AuthenticationPrincipal;

/**
 * The only way a controller obtains the user id: the {@code sub} claim of the validated JWT.
 * Usage: {@code @CurrentUserId UUID userId}. Never accept a user id from the request.
 *
 * <p>PT: A única forma de um controller obter o id do usuário: o campo sub do JWT já validado. Uso:
 * @CurrentUserId UUID userId. Nunca aceite um id de usuário vindo da requisição.
 */
@Target(ElementType.PARAMETER)
@Retention(RetentionPolicy.RUNTIME)
@Documented
@AuthenticationPrincipal(expression = "T(java.util.UUID).fromString(subject)")
public @interface CurrentUserId {
}
