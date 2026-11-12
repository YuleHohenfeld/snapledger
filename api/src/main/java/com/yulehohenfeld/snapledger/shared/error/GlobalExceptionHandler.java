package com.yulehohenfeld.snapledger.shared.error;

import java.sql.SQLException;
import java.util.List;
import java.util.UUID;
import java.util.function.Predicate;
import java.util.stream.Stream;

import jakarta.persistence.PersistenceException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.validation.ConstraintViolation;
import jakarta.validation.ConstraintViolationException;
import jakarta.validation.ElementKind;
import jakarta.validation.Path;

import lombok.extern.slf4j.Slf4j;

import org.hibernate.JDBCException;
import org.springframework.beans.TypeMismatchException;
import org.springframework.context.MessageSourceResolvable;
import org.springframework.core.MethodParameter;
import org.springframework.dao.DataAccessException;
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
@Slf4j
@RestControllerAdvice
public class GlobalExceptionHandler extends ResponseEntityExceptionHandler {

    private static final String INVALID_FIELDS_DETAIL = "One or more fields are invalid.";
    private static final String FALLBACK_FIELD = "request";
    private static final String FALLBACK_MESSAGE = "is invalid";

    @ExceptionHandler(ApiException.class)
    ProblemDetail handleApi(ApiException ex, HttpServletRequest request) {
        return ProblemFactory.create(ex.status(), ex.slug(), ex.getMessage(), request.getRequestURI());
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
            return internalError(ex, request.getRequestURI());
        }
        return validationProblem(violations.stream()
                .map(v -> new InvalidField(lastNodeName(v.getPropertyPath()), messageOf(v.getMessage())))
                .toList(), request.getRequestURI());
    }

    @ExceptionHandler(Exception.class)
    ProblemDetail handleUnexpected(Exception ex, HttpServletRequest request) {
        return internalError(ex, request.getRequestURI());
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
     * replaced by our ProblemDetail. Headers set by Spring (e.g. {@code Allow} on 405,
     * {@code Accept} on 415) are kept.
     *
     * <p>PT: Todo erro do framework termina aqui. Corpos que nós já montamos passam direto; os
     * demais são substituídos pelo nosso ProblemDetail. Headers do Spring (por exemplo Allow
     * no 405, Accept no 415) são mantidos.
     */
    @Override
    protected ResponseEntity<Object> handleExceptionInternal(
            Exception ex, Object body, HttpHeaders headers,
            HttpStatusCode statusCode, WebRequest request) {
        if (isOurs(body)) {
            return super.handleExceptionInternal(ex, body, headers, statusCode, request);
        }
        var path = pathOf(request);
        ProblemDetail problem;
        HttpStatusCode status = statusCode;
        if (statusCode.is5xxServerError()) {
            problem = internalError(ex, path);
            status = HttpStatus.INTERNAL_SERVER_ERROR;
        } else {
            problem = switch (statusCode.value()) {
                case 400 -> ProblemFactory.create(statusCode, Slugs.VALIDATION_ERROR,
                        "The request is malformed or has invalid parameters.", path);
                case 404 -> ProblemFactory.create(statusCode, Slugs.NOT_FOUND, "Resource not found.", path);
                case 405 -> ProblemFactory.create(statusCode, Slugs.METHOD_NOT_ALLOWED,
                        "The HTTP method is not supported for this resource.", path);
                case 406 -> ProblemFactory.create(statusCode, Slugs.NOT_ACCEPTABLE,
                        "The API only produces application/json.", path);
                case 415 -> ProblemFactory.create(statusCode, Slugs.UNSUPPORTED_MEDIA_TYPE,
                        "Content type must be application/json.", path);
                // No slug in the contract for other statuses: keep Spring's ProblemDetail.
                // PT: Não há slug no contrato para outros status: mantém o ProblemDetail do Spring.
                default -> null;
            };
        }
        return super.handleExceptionInternal(ex, problem != null ? problem : body, headers, status, request);
    }

    private ProblemDetail internalError(Exception ex, String path) {
        var errorId = UUID.randomUUID();
        if (firstInCauseChain(ex, GlobalExceptionHandler::isDatabaseError) != null) {
            // Driver messages and their cause chain quote column values (PostgreSQL:
            // "Key (email)=(...) already exists"), so neither the message nor the stack trace
            // is logged. The constraint name is a schema identifier and says what failed.
            // Checked along the whole chain: a database error wrapped by any other exception
            // carries the same message in its cause (and often in the wrapper's own message).
            // PT: As mensagens do driver e a cadeia de causas delas citam valores de colunas
            //     (PostgreSQL: "Key (email)=(...) already exists"), então nem a mensagem nem o
            //     stack trace vão para o log. O nome da constraint é um identificador do esquema e
            //     diz o que falhou. Verificado ao longo de toda a cadeia: um erro de banco
            //     embrulhado por outra exceção carrega a mesma mensagem na causa (e muitas vezes
            //     na própria mensagem da exceção que o embrulha).
            log.error("Unexpected data access error errorId={} exception={} constraint={}",
                    errorId, ex.getClass().getName(), constraintName(ex));
        } else {
            // The full exception stays in the server log; the client only gets the id to report.
            // PT: A exceção completa fica no log do servidor; o cliente recebe só o id para
            //     reportar.
            log.error("Unexpected error errorId={}", errorId, ex);
        }
        var problem = ProblemFactory.create(HttpStatus.INTERNAL_SERVER_ERROR, Slugs.INTERNAL_ERROR,
                "An unexpected error occurred.", path);
        problem.setProperty("errorId", errorId.toString());
        return problem;
    }

    private static boolean isDatabaseError(Throwable ex) {
        return ex instanceof DataAccessException
                || ex instanceof SQLException
                || ex instanceof JDBCException
                || ex instanceof PersistenceException;
    }

    private static String constraintName(Throwable ex) {
        var violation = firstInCauseChain(ex,
                current -> current instanceof org.hibernate.exception.ConstraintViolationException);
        return violation != null
                ? ((org.hibernate.exception.ConstraintViolationException) violation).getConstraintName()
                : null;
    }

    private static Throwable firstInCauseChain(Throwable ex, Predicate<Throwable> matches) {
        for (var current = ex; current != null; current = current.getCause()) {
            if (matches.test(current)) {
                return current;
            }
            if (current.getCause() == current) {
                break;
            }
        }
        return null;
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
