package com.yulehohenfeld.snapledger.shared.security;

import java.io.IOException;

import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;

import org.springframework.http.HttpStatus;
import org.springframework.security.access.AccessDeniedException;
import org.springframework.security.web.access.AccessDeniedHandler;
import org.springframework.stereotype.Component;

import com.yulehohenfeld.snapledger.shared.error.ProblemFactory;
import com.yulehohenfeld.snapledger.shared.error.Slugs;

/**
 * 403 for an authenticated caller who is not allowed to do something, as a ProblemDetail.
 *
 * <p>PT: 403 para quem está autenticado mas não tem permissão para fazer algo, como ProblemDetail.
 */
@Component
public class ProblemDetailAccessDeniedHandler implements AccessDeniedHandler {

    @Override
    public void handle(HttpServletRequest request, HttpServletResponse response,
                       AccessDeniedException accessDeniedException) throws IOException {
        if (response.isCommitted()) {
            return;
        }
        var problem = ProblemFactory.create(HttpStatus.FORBIDDEN, Slugs.FORBIDDEN,
                "You are not allowed to perform this action.", request.getRequestURI());
        ProblemResponseWriter.write(problem, response);
    }
}
