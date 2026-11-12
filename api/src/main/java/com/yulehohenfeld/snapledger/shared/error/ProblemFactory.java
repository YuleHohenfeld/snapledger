package com.yulehohenfeld.snapledger.shared.error;

import java.net.URI;
import java.util.Map;
import java.util.Set;

import org.springframework.http.HttpStatusCode;
import org.springframework.http.ProblemDetail;

/**
 * Builds every error body of the API in the shape promised by docs/api-contract.md "Errors":
 * {@code type = urn:snapledger:problem:<slug>}, a fixed title per slug and the request path
 * as {@code instance}. Used by the MVC exception handler and by the security handlers, so
 * errors look the same whether they happen before or after the controller.
 *
 * <p>PT: Monta todo corpo de erro da API no formato prometido pela seção "Errors" do contrato: type
 * = urn:snapledger:problem:<slug>, um título fixo por slug e o caminho da requisição como
 * instance. É usado pelo handler de exceções do MVC e pelos handlers de segurança, para que
 * os erros tenham a mesma cara aconteçam antes ou depois do controller.
 */
public final class ProblemFactory {

    public static final String TYPE_PREFIX = "urn:snapledger:problem:";

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
     *
     * <p>PT: Lança IllegalArgumentException se o slug não estiver listado no contrato.
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
     * Lets callers fail where the mistake is made (e.g. an ApiException constructor) instead of
     * later, while the error response is being built.
     *
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
