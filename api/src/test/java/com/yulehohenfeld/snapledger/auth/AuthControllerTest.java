package com.yulehohenfeld.snapledger.auth;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.time.Duration;
import java.time.Instant;
import java.util.Map;
import java.util.UUID;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.webmvc.test.autoconfigure.WebMvcTest;
import org.springframework.context.annotation.Import;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.request.MockHttpServletRequestBuilder;

import tools.jackson.databind.json.JsonMapper;

import com.yulehohenfeld.snapledger.auth.dto.AuthResponse;
import com.yulehohenfeld.snapledger.auth.dto.TokenResponse;
import com.yulehohenfeld.snapledger.shared.config.ClockConfig;
import com.yulehohenfeld.snapledger.shared.error.EmailAlreadyRegisteredException;
import com.yulehohenfeld.snapledger.shared.error.InvalidCredentialsException;
import com.yulehohenfeld.snapledger.support.ImportSecurityStack;
import com.yulehohenfeld.snapledger.support.TestTokens;
import com.yulehohenfeld.snapledger.user.dto.UserResponse;

/**
 * The contract of {@code POST /auth/register} and {@code /auth/login} behind the real security
 * chains: status, exact JSON shape, validation without rejected values, cache headers, and chain 1
 * ignoring Authorization (ADR 0005).
 *
 * <p>PT: O contrato de {@code POST /auth/register} e {@code /auth/login} atrás das cadeias de
 * segurança reais: status, formato exato do JSON, validação sem valores rejeitados, headers de
 * cache, e a cadeia 1 ignorando o Authorization (ADR 0005).
 */
@WebMvcTest(AuthController.class)
@ImportSecurityStack
@Import(ClockConfig.class)
class AuthControllerTest {

    static final String REGISTER = "/api/v1/auth/register";
    static final String LOGIN = "/api/v1/auth/login";
    static final String PASSWORD = "pw-" + UUID.randomUUID();
    static final JsonMapper JSON = JsonMapper.builder().build();

    @Autowired
    MockMvc mvc;

    @MockitoBean
    AuthService service;

    final AuthResponse session = new AuthResponse(
            new UserResponse(UUID.randomUUID(), "Ana Souza", "ana@example.com", "BRL",
                    Instant.parse("2026-11-10T14:03:22Z")),
            TokenResponse.bearer("access-value", Duration.ofMinutes(15), "refresh-value", Duration.ofDays(30)));

    @Test
    void registerReturns201WithExactlyTheContractBody() throws Exception {
        when(service.register(any())).thenReturn(session);

        var body = mvc.perform(json(post(REGISTER), registerBody("ana@example.com", PASSWORD)))
                .andExpect(status().isCreated())
                .andExpect(content().contentType(MediaType.APPLICATION_JSON))
                .andExpect(header().doesNotExist(HttpHeaders.LOCATION))
                .andExpect(jsonPath("$.user.id").value(session.user().id().toString()))
                .andExpect(jsonPath("$.user.createdAt").value("2026-11-10T14:03:22Z"))
                .andExpect(jsonPath("$.tokens.accessToken").value("access-value"))
                .andExpect(jsonPath("$.tokens.tokenType").value("Bearer"))
                .andExpect(jsonPath("$.tokens.expiresIn").value(900))
                .andExpect(jsonPath("$.tokens.refreshToken").value("refresh-value"))
                .andExpect(jsonPath("$.tokens.refreshExpiresIn").value(2592000))
                .andReturn().getResponse().getContentAsString();

        assertExactShape(body);
    }

    @Test
    void loginReturns200WithTheSameShape() throws Exception {
        when(service.login(any())).thenReturn(session);

        var body = mvc.perform(json(post(LOGIN), loginBody("ana@example.com", PASSWORD)))
                .andExpect(status().isOk())
                .andReturn().getResponse().getContentAsString();

        assertExactShape(body);
    }

    @ParameterizedTest
    @ValueSource(strings = {REGISTER, LOGIN})
    void tokenResponsesAreNeverCached(String path) throws Exception {
        when(service.register(any())).thenReturn(session);
        when(service.login(any())).thenReturn(session);
        var body = path.equals(REGISTER) ? registerBody("ana@example.com", PASSWORD) : loginBody("ana@example.com", PASSWORD);

        mvc.perform(json(post(path), body))
                .andExpect(header().string(HttpHeaders.CACHE_CONTROL, "no-store"))
                .andExpect(header().string(HttpHeaders.PRAGMA, "no-cache"));
    }

    @Test
    void registerValidationErrorNamesTheFieldButNeverEchoesThePassword() throws Exception {
        var shortPassword = "x" + UUID.randomUUID().toString().substring(0, 5);

        var body = mvc.perform(json(post(REGISTER), registerBody("ana@example.com", shortPassword)))
                .andExpect(status().isBadRequest())
                .andExpect(content().contentTypeCompatibleWith(MediaType.APPLICATION_PROBLEM_JSON))
                .andExpect(jsonPath("$.type").value("urn:snapledger:problem:validation-error"))
                .andExpect(jsonPath("$.errors[0].field").value("password"))
                .andReturn().getResponse().getContentAsString();

        assertThat(body).doesNotContain(shortPassword);
        verifyNoInteractions(service);
    }

    @ParameterizedTest
    @ValueSource(strings = {"josé@example.com", " ana@example.com", "ana@example.com ", "ana @example.com"})
    void registerRejectsAccentsAndWhitespaceInTheEmail(String email) throws Exception {
        var body = mvc.perform(json(post(REGISTER), registerBody(email, PASSWORD)))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.errors[0].field").value("email"))
                .andReturn().getResponse().getContentAsString();

        assertThat(body).doesNotContain(email.strip()).doesNotContain(PASSWORD);
        verifyNoInteractions(service);
    }

    @Test
    void loginValidationErrorNeverEchoesTheEmail() throws Exception {
        var body = mvc.perform(json(post(LOGIN), loginBody("not-an-email", PASSWORD)))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.errors[0].field").value("email"))
                .andReturn().getResponse().getContentAsString();

        assertThat(body).doesNotContain("not-an-email").doesNotContain(PASSWORD);
    }

    @Test
    void takenEmailIs409() throws Exception {
        when(service.register(any())).thenThrow(new EmailAlreadyRegisteredException());

        mvc.perform(json(post(REGISTER), registerBody("ana@example.com", PASSWORD)))
                .andExpect(status().isConflict())
                .andExpect(jsonPath("$.type").value("urn:snapledger:problem:email-already-registered"))
                .andExpect(jsonPath("$.title").value("Email already registered"))
                .andExpect(jsonPath("$.instance").value(REGISTER));
    }

    // Final 401: it carries no Bearer challenge, so the app never tries a refresh (contract).
    // PT: 401 final: não leva desafio Bearer, então o app nunca tenta um refresh (contrato).
    @Test
    void invalidCredentialsIs401WithoutWwwAuthenticate() throws Exception {
        when(service.login(any())).thenThrow(new InvalidCredentialsException());

        mvc.perform(json(post(LOGIN), loginBody("ana@example.com", PASSWORD)))
                .andExpect(status().isUnauthorized())
                .andExpect(header().doesNotExist(HttpHeaders.WWW_AUTHENTICATE))
                .andExpect(jsonPath("$.type").value("urn:snapledger:problem:invalid-credentials"))
                .andExpect(jsonPath("$.title").value("Invalid credentials"));
    }

    @Test
    void malformedJsonIs400() throws Exception {
        mvc.perform(post(LOGIN).contentType(MediaType.APPLICATION_JSON).content("{\"email\":"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.type").value("urn:snapledger:problem:validation-error"));
    }

    @Test
    void nonJsonBodyIs415() throws Exception {
        mvc.perform(post(LOGIN).contentType(MediaType.TEXT_PLAIN).content("x"))
                .andExpect(status().isUnsupportedMediaType());
    }

    // ADR 0005: chain 1 has no JWT filter, so a stale or garbage header changes nothing.
    // PT: ADR 0005: a cadeia 1 não tem filtro de JWT, então um header velho ou lixo não muda nada.
    @ParameterizedTest
    @ValueSource(strings = {"Bearer not-a-jwt", "Basic Zm9vOmJhcg==", "expired"})
    void authEndpointsIgnoreTheAuthorizationHeader(String authorization) throws Exception {
        when(service.register(any())).thenReturn(session);
        when(service.login(any())).thenReturn(session);
        var header = authorization.equals("expired")
                ? TestTokens.bearer(TestTokens.valid(Instant.now().minus(Duration.ofDays(1))))
                : authorization;

        mvc.perform(json(post(REGISTER), registerBody("ana@example.com", PASSWORD))
                        .header(HttpHeaders.AUTHORIZATION, header))
                .andExpect(status().isCreated());
        mvc.perform(json(post(LOGIN), loginBody("ana@example.com", PASSWORD))
                        .header(HttpHeaders.AUTHORIZATION, header))
                .andExpect(status().isOk());
    }

    @ParameterizedTest
    @ValueSource(strings = {"GET " + LOGIN, "GET " + REGISTER, "PUT " + REGISTER, "GET /api/v1/auth/me"})
    void otherMethodsAndPathsUnderAuthAre404WithoutChallenge(String request) throws Exception {
        var parts = request.split(" ");
        var builder = parts[0].equals("GET") ? get(parts[1]) : put(parts[1]);

        mvc.perform(builder.header(HttpHeaders.AUTHORIZATION, "Bearer not-a-jwt"))
                .andExpect(status().isNotFound())
                .andExpect(header().doesNotExist(HttpHeaders.WWW_AUTHENTICATE))
                .andExpect(jsonPath("$.type").value("urn:snapledger:problem:not-found"));
        verifyNoInteractions(service);
    }

    private static void assertExactShape(String body) {
        var tree = JSON.readTree(body);
        assertThat(tree.propertyNames()).containsExactlyInAnyOrder("user", "tokens");
        assertThat(tree.get("user").propertyNames())
                .containsExactlyInAnyOrder("id", "name", "email", "currency", "createdAt");
        assertThat(tree.get("tokens").propertyNames())
                .containsExactlyInAnyOrder("accessToken", "tokenType", "expiresIn", "refreshToken", "refreshExpiresIn");
    }

    private static MockHttpServletRequestBuilder json(MockHttpServletRequestBuilder request, String body) {
        return request.contentType(MediaType.APPLICATION_JSON).content(body);
    }

    private static String registerBody(String email, String password) {
        return JSON.writeValueAsString(Map.of(
                "name", "Ana Souza", "email", email, "password", password, "currency", "BRL"));
    }

    private static String loginBody(String email, String password) {
        return JSON.writeValueAsString(Map.of("email", email, "password", password));
    }
}
