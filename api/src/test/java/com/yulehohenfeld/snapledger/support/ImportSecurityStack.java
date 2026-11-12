package com.yulehohenfeld.snapledger.support;

import java.lang.annotation.Documented;
import java.lang.annotation.ElementType;
import java.lang.annotation.Retention;
import java.lang.annotation.RetentionPolicy;
import java.lang.annotation.Target;

import org.springframework.context.annotation.Import;

import com.yulehohenfeld.snapledger.shared.security.AuthPathNotFoundHandler;
import com.yulehohenfeld.snapledger.shared.security.ProblemDetailAccessDeniedHandler;
import com.yulehohenfeld.snapledger.shared.security.ProblemDetailAuthenticationEntryPoint;
import com.yulehohenfeld.snapledger.shared.security.SecurityConfig;

/**
 * The real security configuration for {@code @WebMvcTest} slices, which do not load our
 * security {@code @Component}s or a JWT secret on their own.
 *
 * <p>The Clock is deliberately not included: SecurityConfig needs one, but tests choose it.
 * Most import {@code ClockConfig}; tests that check token expiry import a fixed clock instead,
 * and having both would define two {@code clock} beans and fail the context. Probes and the
 * clock are added with a separate {@code @Import} on the test class.
 *
 * <p>PT: A configuração de segurança real para fatias {@code @WebMvcTest}, que sozinhas não
 * carregam os nossos {@code @Component}s de segurança nem um segredo de JWT. O Clock fica de fora
 * de propósito: o SecurityConfig precisa de um, mas os testes o escolhem. A maioria importa o
 * {@code ClockConfig}; testes que conferem a expiração do token importam um relógio fixo, e ter os
 * dois definiria dois beans {@code clock} e quebraria o contexto. Probes e o relógio são
 * adicionados com um {@code @Import} separado na classe de teste.
 */
@Target(ElementType.TYPE)
@Retention(RetentionPolicy.RUNTIME)
@Documented
@Import({SecurityConfig.class, ProblemDetailAuthenticationEntryPoint.class,
        ProblemDetailAccessDeniedHandler.class, AuthPathNotFoundHandler.class, TestJwtSecret.class})
public @interface ImportSecurityStack {
}
