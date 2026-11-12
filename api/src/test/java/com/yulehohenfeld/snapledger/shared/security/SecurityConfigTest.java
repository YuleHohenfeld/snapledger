package com.yulehohenfeld.snapledger.shared.security;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.options;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.nio.charset.StandardCharsets;
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.time.ZoneOffset;
import java.util.Base64;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.function.Consumer;

import javax.crypto.Mac;
import javax.crypto.SecretKey;
import javax.crypto.spec.SecretKeySpec;

import jakarta.servlet.DispatcherType;

import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.TestComponent;
import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.boot.webmvc.test.autoconfigure.WebMvcTest;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Import;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.security.oauth2.jose.jws.MacAlgorithm;
import org.springframework.security.oauth2.jwt.JwtClaimNames;
import org.springframework.security.oauth2.jwt.JwtClaimsSet;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.MvcResult;
import org.springframework.test.web.servlet.ResultActions;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RestController;

import com.yulehohenfeld.snapledger.support.ImportSecurityStack;
import com.yulehohenfeld.snapledger.support.TestJwtSecret;
import com.yulehohenfeld.snapledger.support.TestTokens;

/**
 * Both filter chains (ADR 0005), the JWT validators (ADR 0004, ADR 0006), @CurrentUserId and
 * CORS, exercised with real signed tokens against test-only controllers. "Now" is a fixed
 * clock shared by the decoder and the tokens, so expiry tests are exact to the second.
 *
 * <p>PT: As duas cadeias de filtros (ADR 0005), os validadores de JWT (ADR 0004, ADR 0006), o
 * @CurrentUserId e o CORS, exercitados com tokens assinados de verdade contra controllers só de
 * teste. O "agora" é um relógio fixo compartilhado pelo decoder e pelos tokens, então os testes
 * de expiração são exatos até o segundo.
 */
@WebMvcTest(
        controllers = {SecurityConfigTest.ProtectedProbe.class, SecurityConfigTest.AuthProbe.class},
        properties = "app.cors.allowed-origins=" + SecurityConfigTest.ALLOWED_ORIGIN)
@ImportSecurityStack
@Import({SecurityConfigTest.FixedClock.class,
        SecurityConfigTest.ProtectedProbe.class, SecurityConfigTest.AuthProbe.class})
class SecurityConfigTest {

    static final Instant NOW = Instant.parse("2026-11-10T12:00:00Z");
    static final String ALLOWED_ORIGIN = "http://localhost:8081";
    static final String PROTECTED = "/api/v1/probe/me";
    static final String LOGOUT = "/api/v1/auth/logout";
    static final String REFRESH = "/api/v1/auth/refresh";

    @Autowired
    MockMvc mvc;

    @Nested
    class ProtectedEndpoints {

        @Test
        void validTokenPassesAndCurrentUserIdResolvesTheSubject() throws Exception {
            var userId = UUID.randomUUID();

            mvc.perform(get(PROTECTED).header(HttpHeaders.AUTHORIZATION,
                            bearer(token(claims -> claims.subject(userId.toString())))))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.userId").value(userId.toString()));
        }

        @Test
        void audienceListContainingTheApiIsAccepted() throws Exception {
            var token = token(claims -> claims.audience(List.of("another-api", JwtProperties.AUDIENCE)));

            mvc.perform(get(PROTECTED).header(HttpHeaders.AUTHORIZATION, bearer(token)))
                    .andExpect(status().isOk());
        }

        @Test
        void missingTokenReturnsUnauthorizedProblem() throws Exception {
            expectUnauthorized(mvc.perform(get(PROTECTED)));
        }

        @Test
        void tokenExpiredBeyondTheClockSkewIsRejected() throws Exception {
            var token = token(claims -> claims
                    .issuedAt(NOW.minus(Duration.ofMinutes(15)))
                    .expiresAt(NOW.minusSeconds(10)));

            expectUnauthorized(mvc.perform(get(PROTECTED).header(HttpHeaders.AUTHORIZATION, bearer(token))));
        }

        @Test
        void tokenExpiredWithinTheClockSkewIsStillAccepted() throws Exception {
            var token = token(claims -> claims
                    .issuedAt(NOW.minus(Duration.ofMinutes(15)))
                    .expiresAt(NOW.minusSeconds(2)));

            mvc.perform(get(PROTECTED).header(HttpHeaders.AUTHORIZATION, bearer(token)))
                    .andExpect(status().isOk());
        }

        @Test
        void tokenWithoutExpIsRejected() throws Exception {
            expectRejected(token(claims -> claims.claims(c -> c.remove(JwtClaimNames.EXP))));
        }

        @Test
        void tokenWithoutIatIsRejected() throws Exception {
            expectRejected(token(claims -> claims.claims(c -> c.remove(JwtClaimNames.IAT))));
        }

        // Positive control for the hand-signed tests (null iat, alg none...): the same signing
        // helper with valid claims passes, so those rejections come from the claims, not the helper.
        // PT: Controle positivo para os testes assinados à mão (iat nulo, alg none...): o mesmo
        //     helper de assinatura com claims válidas passa, então aquelas recusas vêm das claims,
        //     não do helper.
        @Test
        void handSignedTokenWithValidClaimsIsAccepted() throws Exception {
            mvc.perform(get(PROTECTED).header(HttpHeaders.AUTHORIZATION, bearer(signRawPayload(validClaimsJson()))))
                    .andExpect(status().isOk());
        }

        @Test
        void tokenWithNullIatIsRejected() throws Exception {
            // JwtClaimsSet.Builder cannot emit a null claim, so the payload is signed by hand.
            // PT: O JwtClaimsSet.Builder não consegue emitir uma claim nula, então o payload é
            //     assinado à mão.
            var payload = "{\"sub\":\"" + UUID.randomUUID() + "\",\"iss\":\"" + TestJwtSecret.ISSUER
                    + "\",\"aud\":\"" + JwtProperties.AUDIENCE
                    + "\",\"iat\":null"
                    + ",\"exp\":" + NOW.plus(TestTokens.TTL).getEpochSecond() + "}";

            expectRejected(signRawPayload(payload));
        }

        @Test
        void tokenWithoutSubIsRejected() throws Exception {
            expectRejected(token(claims -> claims.claims(c -> c.remove(JwtClaimNames.SUB))));
        }

        @Test
        void tokenWhoseSubIsNotAUuidIsRejected() throws Exception {
            expectRejected(token(claims -> claims.subject("abc")));
        }

        @Test
        void tokenWhoseSubIsANonCanonicalUuidIsRejected() throws Exception {
            // UUID.fromString accepts this; the validator demands the canonical 36-char form.
            // PT: O UUID.fromString aceita isto; o validador exige a forma canônica de 36 caracteres.
            expectRejected(token(claims -> claims.subject("1-2-3-4-5")));
        }

        @Test
        void tokenWithoutAudIsRejected() throws Exception {
            expectRejected(token(claims -> claims.claims(c -> c.remove(JwtClaimNames.AUD))));
        }

        @Test
        void tokenForAnotherAudienceIsRejected() throws Exception {
            // e.g. a future password-reset JWT replayed as an access token (ADR 0006).
            // PT: por exemplo, um futuro JWT de redefinição de senha reaproveitado como token de
            //     acesso (ADR 0006).
            expectRejected(token(claims -> claims.audience(List.of("snapledger-password-reset"))));
        }

        @Test
        void tamperedTokenReturnsUnauthorizedProblem() throws Exception {
            var parts = token(claims -> { }).split("\\.");
            var tampered = parts[0] + "." + base64Url(validClaimsJson()) + "." + parts[2];

            expectRejected(tampered);
        }

        @Test
        void tokenSignedWithAnotherKeyReturnsUnauthorizedProblem() throws Exception {
            var otherKey = new SecretKeySpec(Base64.getDecoder().decode(TestJwtSecret.generate()), "HmacSHA256");

            expectRejected(sign(otherKey, MacAlgorithm.HS256, claims -> { }));
        }

        @Test
        void wrongIssuerReturnsUnauthorizedProblem() throws Exception {
            expectRejected(token(claims -> claims.issuer("someone-else")));
        }

        @Test
        void algNoneTokenReturnsUnauthorizedProblem() throws Exception {
            var header = base64Url("{\"alg\":\"none\",\"typ\":\"JWT\"}");
            var unsigned = header + "." + base64Url(validClaimsJson()) + ".";

            expectRejected(unsigned);
        }

        @Test
        void tokenWithAnotherHmacAlgorithmIsRejectedBecauseHs256IsPinned() throws Exception {
            expectRejected(sign(TestJwtSecret.key(), MacAlgorithm.HS512, claims -> { }));
        }

        @Test
        void garbageTokenReturnsUnauthorizedProblem() throws Exception {
            expectRejected("not-a-jwt");
        }

        @Test
        void docsPathsArePublic() throws Exception {
            // No token and no such resource: reaching the 404 proves the path skipped authentication.
            // PT: Sem token e sem esse recurso: chegar ao 404 prova que o caminho pulou a
            //     autenticação.
            mvc.perform(get("/docs/index.html"))
                    .andExpect(status().isNotFound())
                    .andExpect(jsonPath("$.type").value("urn:snapledger:problem:not-found"));
        }

        // ADR 0007 permits the ERROR dispatch only to the error path: the dispatcher type alone
        // must never open a protected endpoint.
        // PT: O ADR 0007 permite o dispatch ERROR só para o caminho de erro: o tipo de dispatch
        //     sozinho nunca pode abrir um endpoint protegido.
        @Test
        void errorDispatchToAProtectedPathStillRequiresAToken() throws Exception {
            expectUnauthorized(mvc.perform(get(PROTECTED).with(request -> {
                request.setDispatcherType(DispatcherType.ERROR);
                return request;
            })));
        }

        @Test
        void successfulRequestCreatesNoSessionAndNoCookie() throws Exception {
            var result = mvc.perform(get(PROTECTED).header(HttpHeaders.AUTHORIZATION, bearer(token(claims -> { }))))
                    .andExpect(status().isOk())
                    .andExpect(header().doesNotExist(HttpHeaders.SET_COOKIE))
                    .andReturn();

            expectNoSession(result);
        }

        @Test
        void rejectedRequestCreatesNoSessionAndNoCookie() throws Exception {
            var result = mvc.perform(get(PROTECTED))
                    .andExpect(status().isUnauthorized())
                    .andExpect(header().doesNotExist(HttpHeaders.SET_COOKIE))
                    .andReturn();

            expectNoSession(result);
        }
    }

    @Nested
    class AuthEndpoints {

        @Test
        void logoutIgnoresGarbageAuthorizationHeader() throws Exception {
            mvc.perform(post(LOGOUT).header(HttpHeaders.AUTHORIZATION, "Bearer not-a-jwt"))
                    .andExpect(status().isNoContent());
        }

        @Test
        void refreshIgnoresGarbageAuthorizationHeader() throws Exception {
            mvc.perform(post(REFRESH).header(HttpHeaders.AUTHORIZATION, "Bearer not-a-jwt"))
                    .andExpect(status().isOk());
        }

        @Test
        void logoutIgnoresExpiredAccessToken() throws Exception {
            var expired = token(claims -> claims
                    .issuedAt(NOW.minus(Duration.ofMinutes(20)))
                    .expiresAt(NOW.minus(Duration.ofMinutes(5))));

            mvc.perform(post(LOGOUT).header(HttpHeaders.AUTHORIZATION, bearer(expired)))
                    .andExpect(status().isNoContent());
        }

        @Test
        void sameGarbageHeaderIsStillRejectedOnProtectedEndpoints() throws Exception {
            expectRejected("not-a-jwt");
        }

        @Test
        void unlistedAuthPathIsNotFoundEvenWithAValidToken() throws Exception {
            // Fails closed: chain 1 has no JWT filter, so the caller is anonymous and denyAll() applies.
            // PT: Falha fechado: a cadeia 1 não tem filtro de JWT, então o chamador é anônimo e o
            //     denyAll() se aplica.
            expectAuthPathNotFound(mvc.perform(post("/api/v1/auth/something-else")
                    .header(HttpHeaders.AUTHORIZATION, bearer(token(claims -> { })))), "/api/v1/auth/something-else");
        }

        @Test
        void listedAuthPathWithAnotherMethodIsNotFound() throws Exception {
            expectAuthPathNotFound(mvc.perform(get(LOGOUT)), LOGOUT);
        }
    }

    @Nested
    class Cors {

        @Test
        void allowedOriginReceivesCorsHeaders() throws Exception {
            mvc.perform(get(PROTECTED)
                            .header(HttpHeaders.ORIGIN, ALLOWED_ORIGIN)
                            .header(HttpHeaders.AUTHORIZATION, bearer(token(claims -> { }))))
                    .andExpect(status().isOk())
                    .andExpect(header().string(HttpHeaders.ACCESS_CONTROL_ALLOW_ORIGIN, ALLOWED_ORIGIN));
        }

        @Test
        void disallowedOriginIsRejectedWithoutCorsHeaders() throws Exception {
            mvc.perform(get(PROTECTED)
                            .header(HttpHeaders.ORIGIN, "https://evil.example.com")
                            .header(HttpHeaders.AUTHORIZATION, bearer(token(claims -> { }))))
                    .andExpect(status().isForbidden())
                    .andExpect(header().doesNotExist(HttpHeaders.ACCESS_CONTROL_ALLOW_ORIGIN));
        }

        @Test
        void preflightFromAllowedOriginSucceedsWithoutToken() throws Exception {
            mvc.perform(options(PROTECTED)
                            .header(HttpHeaders.ORIGIN, ALLOWED_ORIGIN)
                            .header(HttpHeaders.ACCESS_CONTROL_REQUEST_METHOD, "GET")
                            .header(HttpHeaders.ACCESS_CONTROL_REQUEST_HEADERS, "authorization"))
                    .andExpect(status().isOk())
                    .andExpect(header().string(HttpHeaders.ACCESS_CONTROL_ALLOW_ORIGIN, ALLOWED_ORIGIN))
                    .andExpect(header().exists(HttpHeaders.ACCESS_CONTROL_ALLOW_METHODS));
        }

        @Test
        void preflightOnAuthEndpointSucceeds() throws Exception {
            mvc.perform(options("/api/v1/auth/login")
                            .header(HttpHeaders.ORIGIN, ALLOWED_ORIGIN)
                            .header(HttpHeaders.ACCESS_CONTROL_REQUEST_METHOD, "POST")
                            .header(HttpHeaders.ACCESS_CONTROL_REQUEST_HEADERS, "content-type"))
                    .andExpect(status().isOk())
                    .andExpect(header().string(HttpHeaders.ACCESS_CONTROL_ALLOW_ORIGIN, ALLOWED_ORIGIN));
        }

        @Test
        void preflightFromDisallowedOriginIsRejected() throws Exception {
            mvc.perform(options(PROTECTED)
                            .header(HttpHeaders.ORIGIN, "https://evil.example.com")
                            .header(HttpHeaders.ACCESS_CONTROL_REQUEST_METHOD, "GET"))
                    .andExpect(status().isForbidden())
                    .andExpect(header().doesNotExist(HttpHeaders.ACCESS_CONTROL_ALLOW_ORIGIN));
        }

        @Test
        void preflightRequestingOnlyAHeaderThatIsNotAllowedIsRejected() throws Exception {
            mvc.perform(options(PROTECTED)
                            .header(HttpHeaders.ORIGIN, ALLOWED_ORIGIN)
                            .header(HttpHeaders.ACCESS_CONTROL_REQUEST_METHOD, "GET")
                            .header(HttpHeaders.ACCESS_CONTROL_REQUEST_HEADERS, "x-debug-user"))
                    .andExpect(status().isForbidden())
                    .andExpect(header().doesNotExist(HttpHeaders.ACCESS_CONTROL_ALLOW_ORIGIN));
        }

        @Test
        void preflightMixingAllowedAndDisallowedHeadersNeverAllowsTheDisallowedOne() throws Exception {
            // Spring answers with the allowed subset; the browser then blocks the real request
            // because x-debug-user is missing from Access-Control-Allow-Headers.
            // PT: O Spring responde com o subconjunto permitido; o navegador então bloqueia a
            //     requisição real porque x-debug-user não está em Access-Control-Allow-Headers.
            var allowHeaders = mvc.perform(options(PROTECTED)
                            .header(HttpHeaders.ORIGIN, ALLOWED_ORIGIN)
                            .header(HttpHeaders.ACCESS_CONTROL_REQUEST_METHOD, "GET")
                            .header(HttpHeaders.ACCESS_CONTROL_REQUEST_HEADERS, "authorization, x-debug-user"))
                    .andReturn().getResponse().getHeaders(HttpHeaders.ACCESS_CONTROL_ALLOW_HEADERS);

            assertThat(String.join(",", allowHeaders)).containsIgnoringCase("authorization")
                    .doesNotContainIgnoringCase("x-debug-user");
        }
    }

    private void expectRejected(String token) throws Exception {
        expectUnauthorized(mvc.perform(get(PROTECTED).header(HttpHeaders.AUTHORIZATION, bearer(token))));
    }

    private static void expectUnauthorized(ResultActions result) throws Exception {
        result.andExpect(status().isUnauthorized())
                .andExpect(header().string(HttpHeaders.WWW_AUTHENTICATE, "Bearer"))
                .andExpect(content().contentTypeCompatibleWith(MediaType.APPLICATION_PROBLEM_JSON))
                .andExpect(jsonPath("$.type").value("urn:snapledger:problem:unauthorized"))
                .andExpect(jsonPath("$.title").value("Unauthorized"))
                .andExpect(jsonPath("$.status").value(401))
                .andExpect(jsonPath("$.detail").value("A valid access token is required."))
                .andExpect(jsonPath("$.instance").exists());
    }

    private static void expectAuthPathNotFound(ResultActions result, String path) throws Exception {
        result.andExpect(status().isNotFound())
                .andExpect(header().doesNotExist(HttpHeaders.WWW_AUTHENTICATE))
                .andExpect(content().contentTypeCompatibleWith(MediaType.APPLICATION_PROBLEM_JSON))
                .andExpect(jsonPath("$.type").value("urn:snapledger:problem:not-found"))
                .andExpect(jsonPath("$.title").value("Not found"))
                .andExpect(jsonPath("$.status").value(404))
                .andExpect(jsonPath("$.instance").value(path));
    }

    private static void expectNoSession(MvcResult result) {
        assertThat(result.getRequest().getSession(false)).isNull();
        assertThat(result.getResponse().getCookies()).isEmpty();
    }

    /**
     * A token that passes every validator, adjusted by {@code customizer} to break exactly one rule.
     *
     * <p>PT: Um token que passa em todos os validadores, ajustado pelo {@code customizer} para quebrar
     * exatamente uma regra.
     */
    private static String token(Consumer<JwtClaimsSet.Builder> customizer) {
        return sign(TestJwtSecret.key(), MacAlgorithm.HS256, customizer);
    }

    private static String sign(SecretKey key, MacAlgorithm alg, Consumer<JwtClaimsSet.Builder> customizer) {
        return TestTokens.sign(key, alg, NOW, customizer);
    }

    /**
     * HS256-signs an arbitrary JSON payload with the application key, for claims the builder cannot express.
     *
     * <p>PT: Assina com HS256 um payload JSON qualquer usando a chave da aplicação, para claims que o
     * builder não consegue expressar.
     */
    private static String signRawPayload(String payloadJson) throws Exception {
        var signingInput = base64Url("{\"alg\":\"HS256\",\"typ\":\"JWT\"}") + "." + base64Url(payloadJson);
        var mac = Mac.getInstance("HmacSHA256");
        mac.init(TestJwtSecret.key());
        var signature = mac.doFinal(signingInput.getBytes(StandardCharsets.US_ASCII));
        return signingInput + "." + Base64.getUrlEncoder().withoutPadding().encodeToString(signature);
    }

    /**
     * Claims that would be accepted if the signature were valid, so only the signature can fail.
     *
     * <p>PT: Claims que seriam aceitas se a assinatura fosse válida, então só a assinatura pode
     * falhar.
     */
    private static String validClaimsJson() {
        return "{\"sub\":\"" + UUID.randomUUID() + "\",\"iss\":\"" + TestJwtSecret.ISSUER
                + "\",\"aud\":\"" + JwtProperties.AUDIENCE
                + "\",\"iat\":" + NOW.getEpochSecond()
                + ",\"exp\":" + NOW.plus(TestTokens.TTL).getEpochSecond() + "}";
    }

    private static String bearer(String token) {
        return TestTokens.bearer(token);
    }

    private static String base64Url(String json) {
        return Base64.getUrlEncoder().withoutPadding().encodeToString(json.getBytes(StandardCharsets.UTF_8));
    }

    @TestConfiguration(proxyBeanMethods = false)
    static class FixedClock {

        @Bean
        Clock clock() {
            return Clock.fixed(NOW, ZoneOffset.UTC);
        }
    }

    // @TestComponent keeps the probes out of every component scan (e.g. @SpringBootTest);
    // they exist only where @Import above registers them.
    // PT: O @TestComponent mantém os probes fora de toda varredura de componentes (por exemplo
    //     @SpringBootTest); eles só existem onde o @Import acima os registra.
    @TestComponent
    @RestController
    static class ProtectedProbe {

        @GetMapping(PROTECTED)
        Map<String, String> me(@CurrentUserId UUID userId) {
            return Map.of("userId", userId.toString());
        }
    }

    @TestComponent
    @RestController
    static class AuthProbe {

        @PostMapping(LOGOUT)
        ResponseEntity<Void> logout() {
            return ResponseEntity.noContent().build();
        }

        @PostMapping(REFRESH)
        ResponseEntity<Void> refresh() {
            return ResponseEntity.ok().build();
        }
    }
}
