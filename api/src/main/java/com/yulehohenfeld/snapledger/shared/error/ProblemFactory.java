package com.yulehohenfeld.snapledger.shared.error;

import java.net.URI;
import java.util.Map;
import java.util.Set;

import org.springframework.http.HttpStatus;
import org.springframework.http.HttpStatusCode;
import org.springframework.http.ProblemDetail;

/**
 * Builds every error body of the API in the shape promised by docs/api-contract.md "Errors":
 * {@code type = urn:snapledger:problem:<slug>}, a fixed title per slug and the request path
 * as {@code instance}. Used by the MVC exception handler, the security handlers,
 * ProblemErrorController (errors the container forwards to /error) and InternalErrors (the 500
 * body), so errors look the same whether they happen before, inside or after the controller.
 *
 * <p>PT: Monta todo corpo de erro da API no formato prometido pela seção "Errors" do contrato: type
 * = urn:snapledger:problem:<slug>, um título fixo por slug e o caminho da requisição como
 * instance. É usado pelo handler de exceções do MVC, pelos handlers de segurança, pelo
 * ProblemErrorController (erros que o container encaminha para /error) e pelo InternalErrors (o
 * corpo 500), para que os erros tenham a mesma cara aconteçam antes, dentro ou depois do
 * controller.
 */
public final class ProblemFactory {

    public static final String TYPE_PREFIX = "urn:snapledger:problem:";

    private static final URI ABOUT_BLANK = URI.create("about:blank");

    // Fixed titles from the contract table. The app branches on type/status, never on title.
    // PT: Títulos fixos, da tabela do contrato. O app decide pelo type/status, nunca pelo título.
    private static final Map<String, String> TITLES = Map.ofEntries(
            Map.entry(Slugs.VALIDATION_ERROR, "Validation failed"),
            Map.entry(Slugs.UNAUTHORIZED, "Unauthorized"),
            Map.entry(Slugs.INVALID_CREDENTIALS, "Invalid credentials"),
            Map.entry(Slugs.INVALID_REFRESH_TOKEN, "Invalid refresh token"),
            Map.entry(Slugs.FORBIDDEN, "Forbidden"),
            Map.entry(Slugs.DEFAULT_CATEGORY_READ_ONLY, "Default category is read-only"),
            Map.entry(Slugs.NOT_FOUND, "Not found"),
            Map.entry(Slugs.METHOD_NOT_ALLOWED, "Method not allowed"),
            Map.entry(Slugs.NOT_ACCEPTABLE, "Not acceptable"),
            Map.entry(Slugs.EMAIL_ALREADY_REGISTERED, "Email already registered"),
            Map.entry(Slugs.CATEGORY_NAME_TAKEN, "Category name taken"),
            Map.entry(Slugs.CATEGORY_IN_USE, "Category in use"),
            Map.entry(Slugs.UNSUPPORTED_MEDIA_TYPE, "Unsupported media type"),
            Map.entry(Slugs.INTERNAL_ERROR, "Internal error"));

    private ProblemFactory() {
    }

    /**
     * Builds the ProblemDetail for a contract slug: type, fixed title, detail and instance.
     *
     * <p>PT: Monta o ProblemDetail de um slug do contrato: type, título fixo, detalhe e
     * instance. Lança IllegalArgumentException se o slug não estiver listado no contrato.
     *
     * @throws IllegalArgumentException if the slug is not listed in the contract
     */
    public static ProblemDetail create(HttpStatusCode status, String slug, String detail, String path) {
        var title = TITLES.get(requireKnownSlug(slug));
        var problem = ProblemDetail.forStatusAndDetail(status, detail);
        problem.setType(URI.create(TYPE_PREFIX + slug));
        problem.setTitle(title);
        problem.setInstance(toInstance(path));
        return problem;
    }

    /**
     * The contract body for a framework or container status that has its own slug, with a fixed
     * detail: 400, 401, 403, 404, 405, 406 and 415. Any other status returns {@code null}; 5xx is
     * not built here because internal-error needs an errorId and a log line (InternalErrors).
     * Never adds {@code WWW-Authenticate}: only the security entry point asks for a token.
     *
     * <p>PT: O corpo do contrato para um status do framework ou do container que tem slug próprio,
     * com um detalhe fixo: 400, 401, 403, 404, 405, 406 e 415. Qualquer outro status devolve
     * {@code null}; 5xx não é montado aqui porque o internal-error precisa de um errorId e de uma
     * linha de log (InternalErrors). Nunca adiciona {@code WWW-Authenticate}: só o entry point de
     * segurança pede token.
     *
     * @return the problem, or {@code null} when the status has no slug of its own here
     */
    public static ProblemDetail forStatus(HttpStatusCode status, String path) {
        return switch (status.value()) {
            case 400 -> create(status, Slugs.VALIDATION_ERROR,
                    "The request is malformed or has invalid parameters.", path);
            case 401 -> create(status, Slugs.UNAUTHORIZED, "A valid access token is required.", path);
            case 403 -> create(status, Slugs.FORBIDDEN, "You are not allowed to perform this action.", path);
            case 404 -> create(status, Slugs.NOT_FOUND, "Resource not found.", path);
            case 405 -> create(status, Slugs.METHOD_NOT_ALLOWED,
                    "The HTTP method is not supported for this resource.", path);
            case 406 -> create(status, Slugs.NOT_ACCEPTABLE, "The API only produces application/json.", path);
            case 415 -> create(status, Slugs.UNSUPPORTED_MEDIA_TYPE, "Content type must be application/json.", path);
            default -> null;
        };
    }

    /**
     * Body for a non-5xx status reported by Spring or by the container: the contract slug when the
     * status has one ({@link #forStatus}), otherwise {@link #aboutBlank}. Shared by
     * GlobalExceptionHandler and ProblemErrorController, so the same status gets the same body
     * whichever of them answers.
     *
     * <p>PT: Corpo para um status que não é 5xx, reportado pelo Spring ou pelo container: o slug do
     * contrato quando o status tem um ({@link #forStatus}), senão {@link #aboutBlank}.
     * Compartilhado pelo GlobalExceptionHandler e pelo ProblemErrorController, para que o mesmo
     * status receba o mesmo corpo, seja qual for o que responde.
     */
    public static ProblemDetail forFrameworkStatus(HttpStatusCode status, String path) {
        var problem = forStatus(status, path);
        return problem != null ? problem : aboutBlank(status, path);
    }

    /**
     * RFC 9457 §4.2.1 body for a status the contract has no slug for (413, 414, 431...):
     * {@code type = about:blank}, the standard reason phrase as title, no detail.
     *
     * <p>PT: Corpo da RFC 9457 §4.2.1 para um status sem slug no contrato (413, 414, 431...):
     * {@code type = about:blank}, a frase padrão do status como título, sem detalhe.
     */
    public static ProblemDetail aboutBlank(HttpStatusCode status, String path) {
        var problem = ProblemDetail.forStatus(status);
        problem.setType(ABOUT_BLANK);
        var known = HttpStatus.resolve(status.value());
        problem.setTitle(known != null ? known.getReasonPhrase() : null);
        problem.setInstance(toInstance(path));
        return problem;
    }

    /**
     * Lets callers fail where the mistake is made (e.g. an ApiException constructor) instead of
     * later, while the error response is being built.
     *
     * <p>PT: Permite que quem chama falhe onde o erro foi cometido (por exemplo, no construtor de
     * uma ApiException), em vez de mais tarde, enquanto a resposta de erro está sendo
     * montada. Retorna o mesmo slug.
     *
     * @return the same slug
     * @throws IllegalArgumentException if the slug is not listed in the contract
     */
    public static String requireKnownSlug(String slug) {
        if (slug == null || !TITLES.containsKey(slug)) {
            throw new IllegalArgumentException("Unknown problem slug: " + slug);
        }
        return slug;
    }

    /**
     * Every slug this factory can build; the contract table and this set must stay identical.
     *
     * <p>PT: Todo slug que esta fábrica sabe montar; a tabela do contrato e este conjunto precisam
     * continuar idênticos.
     */
    static Set<String> knownSlugs() {
        return TITLES.keySet();
    }

    private static URI toInstance(String path) {
        if (path == null || path.isEmpty()) {
            return null;
        }
        try {
            return URI.create(path);
        } catch (IllegalArgumentException e) {
            // A path that is not a valid URI must never turn an error response into a second failure.
            // PT: Um caminho que não é uma URI válida nunca pode transformar uma resposta de erro
            //     numa segunda falha.
            return null;
        }
    }
}
