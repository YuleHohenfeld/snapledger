package com.yulehohenfeld.snapledger.shared.error;

import java.util.List;
import java.util.stream.Stream;

import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import jakarta.validation.ConstraintViolation;
import jakarta.validation.ConstraintViolationException;
import jakarta.validation.ElementKind;
import jakarta.validation.Path;

import org.springframework.beans.TypeMismatchException;
import org.springframework.context.MessageSourceResolvable;
import org.springframework.core.MethodParameter;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatus;
import org.springframework.http.HttpStatusCode;
import org.springframework.http.ProblemDetail;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.AccessDeniedException;
import org.springframework.security.core.AuthenticationException;
import org.springframework.validation.FieldError;
import org.springframework.validation.method.ParameterValidationResult;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.MissingServletRequestParameterException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestControllerAdvice;
import org.springframework.web.context.request.ServletWebRequest;
import org.springframework.web.context.request.WebRequest;
import org.springframework.web.method.annotation.HandlerMethodValidationException;
import org.springframework.web.servlet.mvc.method.annotation.ResponseEntityExceptionHandler;

/**
 * Single place where exceptions become RFC 9457 ProblemDetail bodies (docs/api-contract.md "Errors").
 *
 * <p>Extending {@link ResponseEntityExceptionHandler} routes every framework error (malformed
 * JSON, unknown route, wrong method, wrong content type...) through
 * {@link #handleExceptionInternal}, where it is re-shaped with our slugs and fixed titles.
 * Details are fixed texts on purpose: framework messages can echo client input
 * (rejected values) and may change between Spring versions.
 *
 * <p>PT: Lugar único onde exceções viram corpos ProblemDetail da RFC 9457. Herdar de
 * ResponseEntityExceptionHandler faz todo erro do framework (JSON malformado, rota
 * desconhecida, método errado, tipo de conteúdo errado...) passar por
 * handleExceptionInternal, onde é remodelado com os nossos slugs e títulos fixos. Os
 * detalhes são textos fixos de propósito: mensagens do framework podem repetir o que o
 * cliente enviou (valores rejeitados) e podem mudar entre versões do Spring.
 */
@RestControllerAdvice
public class GlobalExceptionHandler extends ResponseEntityExceptionHandler {

    private static final String INVALID_FIELDS_DETAIL = "One or more fields are invalid.";
    private static final String FALLBACK_FIELD = "request";
    private static final String FALLBACK_MESSAGE = "is invalid";

    /**
     * Domain errors; {@code unauthorized} also gets {@code WWW-Authenticate: Bearer}, like the entry point.
     *
     * <p>PT: Erros do domínio; {@code unauthorized} também recebe {@code WWW-Authenticate: Bearer},
     * como no entry point.
     * Notes: docs/code-notes/security.md#handleapi
     */
    @ExceptionHandler(ApiException.class)
    ResponseEntity<ProblemDetail> handleApi(ApiException ex, HttpServletRequest request) {
        var body = ProblemFactory.create(ex.status(), ex.slug(), ex.getMessage(), request.getRequestURI());
        var response = ResponseEntity.status(ex.status());
        if (Slugs.UNAUTHORIZED.equals(ex.slug())) {
            response.header(HttpHeaders.WWW_AUTHENTICATE, "Bearer");
        }
        return response.body(body);
    }

    /**
     * Security decisions taken inside MVC (e.g. a future {@code @PreAuthorize}) belong to the
     * security layer. Rethrowing the same instance lets ExceptionTranslationFilter answer with
     * the 401/403 ProblemDetail of the chain, instead of the catch-all turning them into a 500.
     *
     * <p>PT: Decisões de segurança tomadas dentro do MVC (por exemplo, um futuro @PreAuthorize)
     * pertencem à camada de segurança. Relançar a mesma instância deixa o
     * ExceptionTranslationFilter responder com o 401/403 da cadeia, em vez de o pega-tudo
     * transformá-las em 500.
     */
    @ExceptionHandler({AccessDeniedException.class, AuthenticationException.class})
    void rethrowSecurityException(RuntimeException ex) {
        throw ex;
    }

    /**
     * Service-level {@code @Validated} failures: same shape as body validation.
     *
     * <p>PT: Falhas de @Validated no nível do Service: mesmo formato da validação do corpo.
     */
    @ExceptionHandler(ConstraintViolationException.class)
    ProblemDetail handleConstraintViolation(ConstraintViolationException ex, HttpServletRequest request) {
        var violations = ex.getConstraintViolations() == null
                ? List.<ConstraintViolation<?>>of()
                : List.copyOf(ex.getConstraintViolations());
        if (violations.stream().anyMatch(GlobalExceptionHandler::isReturnValue)) {
            // An invalid return value is our bug, not bad client input.
            // PT: Um valor de retorno inválido é bug nosso, não entrada ruim do cliente (por isso
            //     500, e não 400).
            return InternalErrors.problem(ex, request.getRequestURI());
        }
        return validationProblem(violations.stream()
                .map(v -> new InvalidField(lastNodeName(v.getPropertyPath()), messageOf(v.getMessage())))
                .toList(), request.getRequestURI());
    }

    /**
     * Catch-all 500. A failure after the response is committed is rethrown (see abortIfCommitted).
     *
     * <p>PT: Pega-tudo 500. Uma falha depois que a resposta foi enviada é relançada (veja
     * abortIfCommitted).
     */
    @ExceptionHandler(Exception.class)
    ProblemDetail handleUnexpected(Exception ex, HttpServletRequest request, HttpServletResponse response)
            throws Exception {
        if (abortIfCommitted(ex, response)) {
            throw ex;
        }
        if (loggedWithoutBody(ex, response, true)) {
            return null;
        }
        return InternalErrors.problem(ex, request.getRequestURI());
    }

    /**
     * {@code @Valid @RequestBody} failures: field + message only, never the rejected value.
     *
     * <p>PT: Falhas de @Valid @RequestBody: só o campo e a mensagem, nunca o valor rejeitado (que
     * poderia ser uma senha).
     */
    @Override
    protected ResponseEntity<Object> handleMethodArgumentNotValid(
            MethodArgumentNotValidException ex, HttpHeaders headers,
            HttpStatusCode status, WebRequest request) {
        var body = validationProblem(ex.getBindingResult().getFieldErrors().stream()
                .map(e -> new InvalidField(e.getField(), messageOf(e.getDefaultMessage())))
                .toList(), pathOf(request));
        return handleExceptionInternal(ex, body, headers, HttpStatus.BAD_REQUEST, request);
    }

    /**
     * Constraints on controller parameters ({@code @RequestParam @Size(...)}, {@code @PathVariable ...}):
     * field is the request-facing parameter name, never the value.
     *
     * <p>PT: Restrições em parâmetros do controller (@RequestParam @Size(...), @PathVariable ...):
     * o campo é o nome do parâmetro como o cliente o enviou, nunca o valor.
     */
    @Override
    protected ResponseEntity<Object> handleHandlerMethodValidationException(
            HandlerMethodValidationException ex, HttpHeaders headers,
            HttpStatusCode status, WebRequest request) {
        if (ex.isForReturnValue()) {
            // Spring reports this as 500; handleExceptionInternal turns it into internal-error.
            // PT: O Spring reporta isto como 500; o handleExceptionInternal o transforma em
            //     internal-error.
            return handleExceptionInternal(ex, null, headers, status, request);
        }
        var body = validationProblem(ex.getParameterValidationResults().stream()
                .flatMap(GlobalExceptionHandler::invalidFields)
                .toList(), pathOf(request));
        return handleExceptionInternal(ex, body, headers, HttpStatus.BAD_REQUEST, request);
    }

    /**
     * Bad UUID, bad YearMonth...: names the parameter, never echoes the value.
     *
     * <p>PT: UUID inválido, YearMonth inválido...: cita o nome do parâmetro, nunca repete o valor.
     */
    @Override
    protected ResponseEntity<Object> handleTypeMismatch(
            TypeMismatchException ex, HttpHeaders headers,
            HttpStatusCode status, WebRequest request) {
        var name = ex.getPropertyName() != null ? ex.getPropertyName() : FALLBACK_FIELD;
        var body = ProblemFactory.create(HttpStatus.BAD_REQUEST, Slugs.VALIDATION_ERROR,
                "Invalid value for parameter '" + name + "'.", pathOf(request));
        return handleExceptionInternal(ex, body, headers, HttpStatus.BAD_REQUEST, request);
    }

    @Override
    protected ResponseEntity<Object> handleMissingServletRequestParameter(
            MissingServletRequestParameterException ex, HttpHeaders headers,
            HttpStatusCode status, WebRequest request) {
        var body = ProblemFactory.create(HttpStatus.BAD_REQUEST, Slugs.VALIDATION_ERROR,
                "Required parameter '" + ex.getParameterName() + "' is missing.", pathOf(request));
        return handleExceptionInternal(ex, body, headers, HttpStatus.BAD_REQUEST, request);
    }

    /**
     * Every framework error ends here. Bodies we already built pass through; the rest are
     * replaced by our ProblemDetail: any 5xx becomes 500 internal-error, any other status gets
     * its contract slug or {@code about:blank} (ProblemFactory.forFrameworkStatus, the same rule
     * as ProblemErrorController). Headers set by Spring (e.g. {@code Allow} on 405,
     * {@code Accept} on 415) are kept. A committed response or a client that went away gets no
     * body (loggedWithoutBody).
     *
     * <p>A failure after commit is not rethrown here, unlike in handleUnexpected: every exception
     * that reaches this method is one Spring's DefaultHandlerExceptionResolver also knows. Rethrown,
     * it is resolved there instead: two WARN lines with the exception's toString, unmasked
     * ("Ignoring exception, response committed already"), Tomcat still ends the response normally
     * and the failure never reaches CommittedResponseFailureFilter. Handling it here at least logs
     * it once, masked.
     *
     * <p>PT: Todo erro do framework termina aqui. Corpos que nós já montamos passam direto; os
     * demais são substituídos pelo nosso ProblemDetail: qualquer 5xx vira 500 internal-error,
     * qualquer outro status recebe o seu slug do contrato ou {@code about:blank}
     * (ProblemFactory.forFrameworkStatus, a mesma regra do ProblemErrorController). Headers do
     * Spring (por exemplo Allow no 405, Accept no 415) são mantidos. Uma resposta já enviada ou um
     * cliente que foi embora não recebe corpo (loggedWithoutBody).
     *
     * <p>PT: Uma falha depois do envio não é relançada aqui, ao contrário do handleUnexpected: toda
     * exceção que chega a este método é uma que o DefaultHandlerExceptionResolver do Spring também
     * conhece. Relançada, ela é resolvida lá: duas linhas WARN com o toString da exceção, sem
     * máscara ("Ignoring exception, response committed already"), o Tomcat termina a resposta
     * normalmente mesmo assim e a falha nunca chega ao CommittedResponseFailureFilter. Tratá-la aqui
     * pelo menos a registra uma vez, mascarada.
     */
    @Override
    protected ResponseEntity<Object> handleExceptionInternal(
            Exception ex, Object body, HttpHeaders headers,
            HttpStatusCode statusCode, WebRequest request) {
        if (loggedWithoutBody(ex, responseOf(request), statusCode.is5xxServerError())) {
            return null;
        }
        if (isOurs(body)) {
            return super.handleExceptionInternal(ex, body, headers, statusCode, request);
        }
        var path = pathOf(request);
        if (statusCode.is5xxServerError()) {
            return super.handleExceptionInternal(ex, InternalErrors.problem(ex, path), headers,
                    HttpStatus.INTERNAL_SERVER_ERROR, request);
        }
        return super.handleExceptionInternal(ex, ProblemFactory.forFrameworkStatus(statusCode, path),
                headers, statusCode, request);
    }

    /**
     * True when the response is already committed and the failure is not a client disconnect:
     * handleUnexpected then rethrows the same instance, without logging. Status and headers are
     * gone, so handling it (returning null) would let Tomcat end the response normally, and the
     * client would get a well-formed but cut body it could take for a whole one. Rethrown, it
     * leaves MVC (no other resolver knows a catch-all exception), CommittedResponseFailureFilter
     * logs it once (masked, {@code responseCommitted=true}) and Tomcat aborts the connection, so
     * the client sees a broken response. The same instance keeps the resolver quiet: it warns
     * ("Failure in @ExceptionHandler") only when a handler throws a different exception.
     *
     * <p>PT: Verdadeiro quando a resposta já foi enviada (committed) e a falha não é uma desconexão
     * do cliente: o handleUnexpected então relança a mesma instância, sem registrar log. Status e
     * headers já saíram, então tratá-la (devolvendo null) deixaria o Tomcat terminar a resposta
     * normalmente, e o cliente receberia um corpo bem formado, mas cortado, que poderia tomar por
     * completo. Relançada, ela sai do MVC (nenhum outro resolver conhece uma exceção do pega-tudo),
     * o CommittedResponseFailureFilter a registra uma vez (mascarada, {@code responseCommitted=true})
     * e o Tomcat aborta a conexão, então o cliente vê uma resposta quebrada. A mesma instância
     * mantém o resolver calado: ele só avisa ("Failure in @ExceptionHandler") quando um handler
     * lança uma exceção diferente.
     */
    private static boolean abortIfCommitted(Exception ex, HttpServletResponse response) {
        return response != null && response.isCommitted() && !InternalErrors.isClientDisconnect(ex);
    }

    /**
     * The cases where no body can or should be written; all are logged here and the caller returns
     * null, which tells Spring the exception is handled and nothing is to be written.
     * <ul>
     * <li>The response is already committed and the failure is not rethrown (a client disconnect,
     * or any framework error in handleExceptionInternal): one line through
     * InternalErrors.logCommitted, masked and marked {@code responseCommitted=true}. Returning null
     * also skips the base class's WARN, which prints the exception's toString unmasked. Handled
     * here, so it never reaches CommittedResponseFailureFilter and is not logged twice.</li>
     * <li>The client went away before commit ({@code checkDisconnect}, only for what would be a
     * 5xx): one DEBUG line, nobody is left to read a body. The status is set to 500 so nothing that
     * reads it (an access log, a proxy, a test) records the default 200, a success that never
     * happened.</li>
     * </ul>
     *
     * <p>PT: Os casos em que nenhum corpo pode ou deve ser escrito; todos são registrados aqui e quem
     * chama devolve null, o que diz ao Spring que a exceção foi tratada e que não há nada a escrever.
     * Resposta já enviada (committed) e falha não relançada (uma desconexão do cliente, ou qualquer
     * erro do framework no handleExceptionInternal): uma linha pelo InternalErrors.logCommitted,
     * mascarada e marcada com {@code responseCommitted=true}. Devolver null também evita o WARN da
     * classe base, que imprime o toString da exceção sem máscara. Tratada aqui, então nunca chega ao
     * CommittedResponseFailureFilter e não é registrada duas vezes.
     * Cliente que foi embora antes do envio ({@code checkDisconnect}, só para o que seria um 5xx):
     * uma linha DEBUG, não sobrou ninguém para ler um corpo. O status vira 500 para que nada que o
     * leia (um access log, um proxy, um teste) registre o 200 padrão, um sucesso que nunca
     * aconteceu.
     */
    private static boolean loggedWithoutBody(Exception ex, HttpServletResponse response, boolean checkDisconnect) {
        if (response != null && response.isCommitted()) {
            InternalErrors.logCommitted(ex);
            return true;
        }
        if (checkDisconnect && InternalErrors.isClientDisconnect(ex)) {
            if (response != null) {
                response.setStatus(HttpStatus.INTERNAL_SERVER_ERROR.value());
            }
            InternalErrors.logClientDisconnect(ex);
            return true;
        }
        return false;
    }

    private static HttpServletResponse responseOf(WebRequest request) {
        return request instanceof ServletWebRequest servlet ? servlet.getResponse() : null;
    }

    private static ProblemDetail validationProblem(List<InvalidField> errors, String path) {
        var body = ProblemFactory.create(HttpStatus.BAD_REQUEST, Slugs.VALIDATION_ERROR, INVALID_FIELDS_DETAIL, path);
        body.setProperty("errors", errors);
        return body;
    }

    /**
     * Field errors of a validated object keep their field name; plain parameters use the parameter
     * name.
     *
     * <p>PT: Erros de campo de um objeto validado mantêm o nome do campo; parâmetros simples usam o
     * nome do parâmetro.
     */
    private static Stream<InvalidField> invalidFields(ParameterValidationResult result) {
        var parameter = parameterName(result.getMethodParameter());
        return result.getResolvableErrors().stream()
                .map(error -> new InvalidField(
                        error instanceof FieldError field ? field.getField() : parameter,
                        messageOf(error)));
    }

    /**
     * The name the client sent ({@code @RequestParam("month")}), falling back to the Java name.
     *
     * <p>PT: O nome que o cliente enviou (@RequestParam("month")), usando o nome Java como plano B.
     */
    private static String parameterName(MethodParameter parameter) {
        var requestParam = parameter.getParameterAnnotation(RequestParam.class);
        if (requestParam != null) {
            return firstNonEmpty(requestParam.name(), requestParam.value(), parameter.getParameterName());
        }
        var pathVariable = parameter.getParameterAnnotation(PathVariable.class);
        if (pathVariable != null) {
            return firstNonEmpty(pathVariable.name(), pathVariable.value(), parameter.getParameterName());
        }
        var requestHeader = parameter.getParameterAnnotation(RequestHeader.class);
        if (requestHeader != null) {
            return firstNonEmpty(requestHeader.name(), requestHeader.value(), parameter.getParameterName());
        }
        return firstNonEmpty(parameter.getParameterName());
    }

    private static String firstNonEmpty(String... candidates) {
        for (var candidate : candidates) {
            if (candidate != null && !candidate.isEmpty()) {
                return candidate;
            }
        }
        return FALLBACK_FIELD;
    }

    private static boolean isReturnValue(ConstraintViolation<?> violation) {
        for (Path.Node node : violation.getPropertyPath()) {
            if (node.getKind() == ElementKind.RETURN_VALUE) {
                return true;
            }
        }
        return false;
    }

    /**
     * "register.request.email" -> "email"; "check.code" -> "code".
     *
     * <p>PT: "register.request.email" vira "email"; "check.code" vira "code".
     */
    private static String lastNodeName(Path path) {
        String name = null;
        for (Path.Node node : path) {
            name = node.getName();
        }
        return firstNonEmpty(name);
    }

    private static String messageOf(MessageSourceResolvable error) {
        return messageOf(error.getDefaultMessage());
    }

    private static String messageOf(String message) {
        return message != null ? message : FALLBACK_MESSAGE;
    }

    private static boolean isOurs(Object body) {
        return body instanceof ProblemDetail problem
                && problem.getType() != null
                && problem.getType().toString().startsWith(ProblemFactory.TYPE_PREFIX);
    }

    private static String pathOf(WebRequest request) {
        return request instanceof ServletWebRequest servlet ? servlet.getRequest().getRequestURI() : null;
    }

    /**
     * One entry of the {@code errors} property of a validation-error.
     *
     * <p>PT: Um item da propriedade errors de um validation-error.
     */
    public record InvalidField(String field, String message) {
    }
}
