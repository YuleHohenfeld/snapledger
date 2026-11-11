package com.yulehohenfeld.snapledger.shared.security;

import java.io.IOException;

import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;

import org.springframework.http.HttpStatus;
import org.springframework.security.access.AccessDeniedException;
import org.springframework.security.core.AuthenticationException;
import org.springframework.security.web.AuthenticationEntryPoint;
import org.springframework.security.web.access.AccessDeniedHandler;
import org.springframework.stereotype.Component;

import com.yulehohenfeld.snapledger.shared.error.ProblemFactory;
import com.yulehohenfeld.snapledger.shared.error.Slugs;

/**
 * Chain 1 ({@code /api/v1/auth/**}) answer for any path or method the contract does not list:
 * {@code 404 not-found}, the same body as an unknown route, and no {@code WWW-Authenticate}.
 * The auth endpoints never read the Authorization header (ADR 0005), so "token required"
 * would be a lie that sends the client into a pointless refresh. Both interfaces are
 * implemented because {@code denyAll()} reaches the entry point for anonymous callers and the
 * access-denied handler otherwise; chain 1 has no authentication, but both must fail the same way.
 */
@Component
public class AuthPathNotFoundHandler implements AuthenticationEntryPoint, AccessDeniedHandler {

    @Override
    public void commence(HttpServletRequest request, HttpServletResponse response,
                         AuthenticationException authException) throws IOException {
        writeNotFound(request, response);
    }

    @Override
    public void handle(HttpServletRequest request, HttpServletResponse response,
                       AccessDeniedException accessDeniedException) throws IOException {
        writeNotFound(request, response);
    }

    private static void writeNotFound(HttpServletRequest request, HttpServletResponse response) throws IOException {
        if (response.isCommitted()) {
            return;
        }
        var problem = ProblemFactory.create(HttpStatus.NOT_FOUND, Slugs.NOT_FOUND,
                "Resource not found.", request.getRequestURI());
        ProblemResponseWriter.write(problem, response);
    }
}
