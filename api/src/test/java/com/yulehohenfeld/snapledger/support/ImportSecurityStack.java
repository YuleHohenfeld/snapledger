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
 */
@Target(ElementType.TYPE)
@Retention(RetentionPolicy.RUNTIME)
@Documented
@Import({SecurityConfig.class, ProblemDetailAuthenticationEntryPoint.class,
        ProblemDetailAccessDeniedHandler.class, AuthPathNotFoundHandler.class, TestJwtSecret.class})
public @interface ImportSecurityStack {
}
