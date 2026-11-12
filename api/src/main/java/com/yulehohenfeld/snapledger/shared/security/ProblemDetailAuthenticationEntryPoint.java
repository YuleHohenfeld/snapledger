package com.yulehohenfeld.snapledger.shared.security;

import java.io.IOException;

import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;

import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatus;
import org.springframework.security.core.AuthenticationException;
import org.springframework.security.web.AuthenticationEntryPoint;
import org.springframework.stereotype.Component;

import com.yulehohenfeld.snapledger.shared.error.ProblemFactory;
import com.yulehohenfeld.snapledger.shared.error.Slugs;

/**
 * 401 for a missing, malformed, tampered or expired access token, as a ProblemDetail.
 * The detail is the same for every reason: the client only needs to know it must refresh
 * or log in again, and an attacker learns nothing about why a forged token failed.
 *
 * <p>PT: 401 para um token de acesso ausente, malformado, adulterado ou vencido, como
 * ProblemDetail. O detalhe é o mesmo para todos os motivos: o cliente só precisa saber que
 * deve fazer refresh ou logar de novo, e um atacante não aprende nada sobre por que o token
 * forjado falhou.
 */
@Component
public class ProblemDetailAuthenticationEntryPoint implements AuthenticationEntryPoint {

    @Override
    public void commence(HttpServletRequest request, HttpServletResponse response,
                         AuthenticationException authException) throws IOException {
        if (response.isCommitted()) {
            return;
        }
        response.setHeader(HttpHeaders.WWW_AUTHENTICATE, "Bearer"); // RFC 6750
        // PT: RFC 6750: a especificação de como tokens Bearer são enviados
        var problem = ProblemFactory.create(HttpStatus.UNAUTHORIZED, Slugs.UNAUTHORIZED,
                "A valid access token is required.", request.getRequestURI());
        ProblemResponseWriter.write(problem, response);
    }
}
