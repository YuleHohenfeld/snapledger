package com.yulehohenfeld.snapledger.shared.config;

import java.net.URI;
import java.net.URISyntaxException;
import java.util.List;

import org.springframework.boot.context.properties.ConfigurationProperties;

/**
 * Browser origins allowed by CORS, from {@code CORS_ALLOWED_ORIGINS} (comma-separated).
 * Blank means no browser origin is allowed (the mobile app does not need CORS).
 * Each entry must be an exact origin ({@code scheme://host[:port]}, http or https); anything
 * else fails startup (api/CLAUDE.md security rule 2). A browser compares origins as plain
 * strings, so a typo such as a trailing slash would silently allow nothing, and the literal
 * {@code null} would allow sandboxed iframes and {@code file://} pages.
 *
 * <p>PT: Origens de navegador permitidas pelo CORS, vindas de CORS_ALLOWED_ORIGINS (separadas por
 * vírgula). Vazio significa que nenhuma origem de navegador é permitida (o app mobile não
 * precisa de CORS). Cada item precisa ser uma origem exata (protocolo://domínio[:porta],
 * http ou https); qualquer outra coisa impede a API de subir (regra de segurança 2 do
 * api/CLAUDE.md). O navegador compara origens como texto puro, então um erro de digitação,
 * como uma barra no final, silenciosamente não liberaria nada, e o texto literal null
 * liberaria iframes isolados e páginas file://.
 */
@ConfigurationProperties("app.cors")
public record CorsProperties(List<String> allowedOrigins) {

    public CorsProperties {
        allowedOrigins = allowedOrigins == null ? List.of() : allowedOrigins.stream()
                .map(String::trim)
                .filter(origin -> !origin.isEmpty())
                .toList();
        allowedOrigins.forEach(CorsProperties::requireExactOrigin);
    }

    // Origins are public values (browsers send them in every request), so naming the entry is safe.
    // PT: Origens são valores públicos (o navegador as envia em toda requisição), então citar o
    //     item inválido na mensagem é seguro.
    private static void requireExactOrigin(String origin) {
        if (origin.contains("*")) {
            throw invalid(origin, "wildcards are not allowed");
        }
        if (origin.equalsIgnoreCase("null")) {
            throw invalid(origin, "the 'null' origin is not allowed");
        }
        URI uri;
        try {
            uri = new URI(origin);
        } catch (URISyntaxException e) {
            throw invalid(origin, "not a valid URI");
        }
        var scheme = uri.getScheme();
        if (scheme == null || !(scheme.equalsIgnoreCase("http") || scheme.equalsIgnoreCase("https"))) {
            throw invalid(origin, "scheme must be http or https");
        }
        if (uri.getHost() == null) {
            throw invalid(origin, "host is required");
        }
        if (uri.getRawUserInfo() != null) {
            throw invalid(origin, "user info is not allowed");
        }
        if (uri.getRawPath() != null && !uri.getRawPath().isEmpty()) {
            throw invalid(origin, "path is not allowed (not even a trailing slash)");
        }
        if (uri.getRawQuery() != null || uri.getRawFragment() != null) {
            throw invalid(origin, "query and fragment are not allowed");
        }
    }

    private static IllegalArgumentException invalid(String origin, String reason) {
        return new IllegalArgumentException("app.cors.allowed-origins (CORS_ALLOWED_ORIGINS) has an invalid origin '"
                + origin + "': " + reason + ". Expected scheme://host[:port], e.g. https://app.example.com");
    }
}
