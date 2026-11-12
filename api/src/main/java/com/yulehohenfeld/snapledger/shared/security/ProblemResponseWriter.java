package com.yulehohenfeld.snapledger.shared.security;

import java.io.IOException;

import jakarta.servlet.http.HttpServletResponse;

import org.springframework.http.MediaType;
import org.springframework.http.ProblemDetail;
import org.springframework.http.converter.json.JacksonJsonHttpMessageConverter;
import org.springframework.http.server.ServletServerHttpResponse;

/**
 * Writes a ProblemDetail from a security filter, where MVC's message converters are not in play.
 * The no-arg converter registers Spring's ProblemDetail mixin, so custom properties are
 * rendered at the top level exactly as in responses produced by GlobalExceptionHandler.
 *
 * <p>PT: Escreve um ProblemDetail a partir de um filtro de segurança, onde os conversores de
 * mensagem do MVC não estão em ação. O conversor sem argumentos registra o mixin de
 * ProblemDetail do Spring, então propriedades extras saem no nível de cima do JSON, igual às
 * respostas do GlobalExceptionHandler.
 */
final class ProblemResponseWriter {

    private static final JacksonJsonHttpMessageConverter CONVERTER = new JacksonJsonHttpMessageConverter();

    private ProblemResponseWriter() {
    }

    static void write(ProblemDetail problem, HttpServletResponse response) throws IOException {
        response.setStatus(problem.getStatus());
        CONVERTER.write(problem, MediaType.APPLICATION_PROBLEM_JSON, new ServletServerHttpResponse(response));
    }
}
