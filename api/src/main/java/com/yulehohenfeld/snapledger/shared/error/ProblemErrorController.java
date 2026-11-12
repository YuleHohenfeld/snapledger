package com.yulehohenfeld.snapledger.shared.error;

import jakarta.servlet.RequestDispatcher;
import jakarta.servlet.http.HttpServletRequest;

import org.springframework.boot.webmvc.error.ErrorController;
import org.springframework.http.CacheControl;
import org.springframework.http.HttpStatus;
import org.springframework.http.HttpStatusCode;
import org.springframework.http.MediaType;
import org.springframework.http.ProblemDetail;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * Owns {@code /error}, where the servlet container forwards errors that never reached
 * GlobalExceptionHandler: a URL rejected by the security firewall, an exception thrown by a filter
 * or while writing the response (ADR 0007). Replaces Boot's BasicErrorController, so these errors
 * keep their real status and use the contract's ProblemDetail format.
 *
 * <p>Everything here is written so it cannot throw: an error inside the error dispatch has no
 * further fallback. Request attributes are type-checked, never cast blindly, and the 5xx path goes
 * through InternalErrors, which never throws (only a fatal JVM error such as OutOfMemoryError
 * passes).
 *
 * <p>PT: Dono de {@code /error}, para onde o servlet container encaminha erros que nunca chegaram
 * ao GlobalExceptionHandler: uma URL recusada pelo firewall de segurança, uma exceção lançada por
 * um filtro ou durante a escrita da resposta (ADR 0007). Substitui o BasicErrorController do Boot,
 * para que esses erros mantenham o status real e usem o formato ProblemDetail do contrato. Tudo
 * aqui é escrito para não poder lançar exceção: um erro dentro do error dispatch não tem mais
 * nenhum plano B. Os atributos da requisição são conferidos por tipo, nunca convertidos às cegas,
 * e o caminho 5xx passa pelo InternalErrors, que nunca lança exceção (só um erro fatal da JVM, como
 * OutOfMemoryError, passa).
 */
@RestController
public class ProblemErrorController implements ErrorController {

    static final String X_CONTENT_TYPE_OPTIONS = "X-Content-Type-Options";

    /**
     * Every HTTP method: the forward keeps the original method (a failed POST arrives as POST).
     * The Content-Type is set explicitly, so an {@code Accept: text/html} cannot turn the error
     * into a 406 inside the error dispatch.
     *
     * <p>Spring Security's header filter skips ERROR dispatches and the firewall rejects a request
     * before that filter runs, so these responses would otherwise have no {@code nosniff} and no
     * cache rule. Both are set here: a browser must not guess another content type, and no cache
     * may keep an error body.
     *
     * <p>PT: Todo método HTTP: o encaminhamento mantém o método original (um POST que falhou chega
     * como POST). O Content-Type é definido explicitamente, então um {@code Accept: text/html} não
     * consegue transformar o erro num 406 dentro do error dispatch. O filtro de headers do Spring
     * Security pula dispatches ERROR, e o firewall recusa a requisição antes de esse filtro rodar,
     * então estas respostas ficariam sem {@code nosniff} e sem regra de cache. Os dois são definidos
     * aqui: o navegador não pode adivinhar outro tipo de conteúdo, e nenhum cache pode guardar um
     * corpo de erro.
     */
    @RequestMapping("${server.error.path:/error}")
    public ResponseEntity<ProblemDetail> error(HttpServletRequest request) {
        var problem = problemFor(request);
        return ResponseEntity.status(problem.getStatus())
                .contentType(MediaType.APPLICATION_PROBLEM_JSON)
                .header(X_CONTENT_TYPE_OPTIONS, "nosniff")
                .cacheControl(CacheControl.noStore())
                .body(problem);
    }

    private static ProblemDetail problemFor(HttpServletRequest request) {
        var path = pathOf(request);
        var status = statusOf(request.getAttribute(RequestDispatcher.ERROR_STATUS_CODE));
        if (status == null) {
            // No usable status means this is not a container error dispatch: an authenticated
            // client called /error directly. To that client it is just a route that does not exist.
            // PT: Sem status utilizável, isto não é um error dispatch do container: um cliente
            //     autenticado chamou /error diretamente. Para ele, é só uma rota que não existe.
            return ProblemFactory.forStatus(HttpStatus.NOT_FOUND, path);
        }
        if (status.is5xxServerError()) {
            var exception = request.getAttribute(RequestDispatcher.ERROR_EXCEPTION);
            return InternalErrors.problem(exception instanceof Throwable t ? t : null, path);
        }
        return ProblemFactory.forFrameworkStatus(status, path);
    }

    /**
     * Only 4xx and 5xx are errors; anything else (missing, not an Integer, out of range) is
     * treated as no status at all.
     *
     * <p>PT: Só 4xx e 5xx são erros; qualquer outra coisa (ausente, não Integer, fora da faixa) é
     * tratada como se não houvesse status.
     */
    private static HttpStatusCode statusOf(Object attribute) {
        if (attribute instanceof Integer code && code >= 400 && code <= 599) {
            return HttpStatusCode.valueOf(code);
        }
        return null;
    }

    /**
     * The original path, never the query string: queries can carry values the client typed.
     * Falls back to this request's own path when the container did not set one.
     *
     * <p>PT: O caminho original, nunca a query string: queries podem trazer valores digitados pelo
     * cliente. Usa o próprio caminho desta requisição quando o container não definiu um.
     */
    private static String pathOf(HttpServletRequest request) {
        var original = request.getAttribute(RequestDispatcher.ERROR_REQUEST_URI);
        var path = original instanceof String uri ? uri : request.getRequestURI();
        if (path == null) {
            return null;
        }
        var end = path.indexOf('?');
        return end >= 0 ? path.substring(0, end) : path;
    }
}
