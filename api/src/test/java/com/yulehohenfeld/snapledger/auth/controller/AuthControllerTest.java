package com.yulehohenfeld.snapledger.auth.controller;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.verify;
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
import java.util.concurrent.ThreadLocalRandom;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.CsvSource;
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
import com.yulehohenfeld.snapledger.auth.dto.RefreshRequest;
import com.yulehohenfeld.snapledger.auth.dto.TokenResponse;
import com.yulehohenfeld.snapledger.auth.service.AuthService;
import com.yulehohenfeld.snapledger.auth.dto.IssuedToken;
import com.yulehohenfeld.snapledger.auth.service.PasswordResetService;
import com.yulehohenfeld.snapledger.shared.error.InvalidCodeException;
import com.yulehohenfeld.snapledger.shared.error.InvalidResetTokenException;
import com.yulehohenfeld.snapledger.shared.ratelimit.RateLimitProperties;
import com.yulehohenfeld.snapledger.shared.config.ClockConfig;
import com.yulehohenfeld.snapledger.shared.error.EmailAlreadyRegisteredException;
import com.yulehohenfeld.snapledger.shared.error.InvalidCredentialsException;
import com.yulehohenfeld.snapledger.shared.error.InvalidRefreshTokenException;
import com.yulehohenfeld.snapledger.support.ImportSecurityStack;
import com.yulehohenfeld.snapledger.support.TestTokens;
import com.yulehohenfeld.snapledger.user.dto.UserResponse;

/**
 * The contract of {@code POST /auth/register}, {@code /login}, {@code /refresh} and {@code /logout}
 * behind the real security chains: status, exact JSON shape, validation without rejected values,
 * cache headers, and chain 1 ignoring Authorization (ADR 0005).
 *
 * <p>PT: O contrato de {@code POST /auth/register}, {@code /login}, {@code /refresh} e
 * {@code /logout} atrás das cadeias de
 * segurança reais: status, formato exato do JSON, validação sem valores rejeitados, headers de
 * cache, e a cadeia 1 ignorando o Authorization (ADR 0005).
 */
@WebMvcTest(AuthController.class)
@ImportSecurityStack
@Import(ClockConfig.class)
class AuthControllerTest {

    static final String REGISTER = "/api/v1/auth/register";
    static final String LOGIN = "/api/v1/auth/login";
    static final String REFRESH = "/api/v1/auth/refresh";
    static final String LOGOUT = "/api/v1/auth/logout";
    static final String RESET = "/api/v1/auth/password-reset";
    static final String VERIFY = "/api/v1/auth/password-reset/verify";
    static final String CONFIRM = "/api/v1/auth/password-reset/confirm";
    static final String PASSWORD = "pw-" + UUID.randomUUID();
    static final JsonMapper JSON = JsonMapper.builder().build();

    @Autowired
    MockMvc mvc;

    @MockitoBean
    AuthService service;

    @MockitoBean
    PasswordResetService passwordReset;

    @Autowired
    RateLimitProperties limits;

    final AuthResponse session = new AuthResponse(
            new UserResponse(UUID.randomUUID(), "Ana Souza", "ana@example.com", "BRL",
                    Instant.parse("2026-11-10T14:03:22Z"), false),
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

    // --- refresh and logout ---
    // PT: --- refresh e logout ---

    @Test
    void refreshReturns200WithExactlyATokenResponse() throws Exception {
        when(service.refresh(any())).thenReturn(session.tokens());

        var body = mvc.perform(json(post(REFRESH), refreshBody("old-refresh")))
                .andExpect(status().isOk())
                .andExpect(content().contentType(MediaType.APPLICATION_JSON))
                .andExpect(header().string(HttpHeaders.CACHE_CONTROL, "no-store"))
                .andExpect(header().string(HttpHeaders.PRAGMA, "no-cache"))
                .andExpect(jsonPath("$.accessToken").value("access-value"))
                .andExpect(jsonPath("$.tokenType").value("Bearer"))
                .andExpect(jsonPath("$.expiresIn").value(900))
                .andExpect(jsonPath("$.refreshToken").value("refresh-value"))
                .andExpect(jsonPath("$.refreshExpiresIn").value(2592000))
                .andReturn().getResponse().getContentAsString();

        assertThat(JSON.readTree(body).propertyNames())
                .containsExactlyInAnyOrder("accessToken", "tokenType", "expiresIn", "refreshToken", "refreshExpiresIn");
        verify(service).refresh(new RefreshRequest("old-refresh"));
    }

    // Final 401: no Bearer challenge, the app wipes the session instead of retrying (contract).
    // PT: 401 final: sem desafio Bearer, o app apaga a sessão em vez de tentar de novo (contrato).
    @Test
    void invalidRefreshTokenIs401ProblemWithoutWwwAuthenticate() throws Exception {
        when(service.refresh(any())).thenThrow(new InvalidRefreshTokenException());

        var body = mvc.perform(json(post(REFRESH), refreshBody("old-refresh")))
                .andExpect(status().isUnauthorized())
                .andExpect(content().contentTypeCompatibleWith(MediaType.APPLICATION_PROBLEM_JSON))
                .andExpect(header().doesNotExist(HttpHeaders.WWW_AUTHENTICATE))
                .andExpect(jsonPath("$.type").value("urn:snapledger:problem:invalid-refresh-token"))
                .andExpect(jsonPath("$.title").value("Invalid refresh token"))
                .andExpect(jsonPath("$.instance").value(REFRESH))
                .andReturn().getResponse().getContentAsString();

        assertThat(body).doesNotContain("old-refresh");
    }

    @Test
    void logoutReturns204WithAnEmptyBody() throws Exception {
        mvc.perform(json(post(LOGOUT), refreshBody("some-refresh")))
                .andExpect(status().isNoContent())
                .andExpect(content().string(""));

        verify(service).logout(new RefreshRequest("some-refresh"));
    }

    @ParameterizedTest
    @ValueSource(strings = {REFRESH, LOGOUT})
    void aMissingRefreshTokenIs400OnTheField(String path) throws Exception {
        mvc.perform(json(post(path), "{}"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.type").value("urn:snapledger:problem:validation-error"))
                .andExpect(jsonPath("$.errors[0].field").value("refreshToken"));
        verifyNoInteractions(service);
    }

    // Blank or over 256 chars: 400 on the field, and the body never repeats what was sent.
    // PT: Vazio ou acima de 256 chars: 400 no campo, e o corpo nunca repete o que foi enviado.
    @ParameterizedTest
    @CsvSource({REFRESH + ",blank", REFRESH + ",long", LOGOUT + ",blank", LOGOUT + ",long"})
    void aBlankOrTooLongRefreshTokenIs400WithoutEchoingIt(String path, String kind) throws Exception {
        var token = kind.equals("blank") ? "   " : "x".repeat(221) + UUID.randomUUID(); // 257 chars
        // PT: 257 chars

        var body = mvc.perform(json(post(path), refreshBody(token)))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.type").value("urn:snapledger:problem:validation-error"))
                .andExpect(jsonPath("$.errors.length()").value(1))
                .andExpect(jsonPath("$.errors[0].field").value("refreshToken"))
                .andReturn().getResponse().getContentAsString();

        assertThat(body).doesNotContain("xxxxxxxx");
        verifyNoInteractions(service);
    }

    @ParameterizedTest
    @ValueSource(strings = {REFRESH, LOGOUT})
    void malformedJsonOnRefreshAndLogoutIs400(String path) throws Exception {
        mvc.perform(post(path).contentType(MediaType.APPLICATION_JSON).content("{\"refreshToken\":"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.type").value("urn:snapledger:problem:validation-error"));
        verifyNoInteractions(service);
    }

    @ParameterizedTest
    @ValueSource(strings = {REFRESH, LOGOUT})
    void nonJsonBodyOnRefreshAndLogoutIs415(String path) throws Exception {
        mvc.perform(post(path).contentType(MediaType.TEXT_PLAIN).content("x"))
                .andExpect(status().isUnsupportedMediaType());
        verifyNoInteractions(service);
    }

    // ADR 0005: chain 1 has no JWT filter, so a stale or garbage header changes nothing.
    // PT: ADR 0005: a cadeia 1 não tem filtro de JWT, então um header velho ou lixo não muda nada.
    @ParameterizedTest
    @ValueSource(strings = {"Bearer not-a-jwt", "Basic Zm9vOmJhcg==", "expired"})
    void authEndpointsIgnoreTheAuthorizationHeader(String authorization) throws Exception {
        when(service.register(any())).thenReturn(session);
        when(service.login(any())).thenReturn(session);
        when(service.refresh(any())).thenReturn(session.tokens());
        var header = authorization.equals("expired")
                ? TestTokens.bearer(TestTokens.valid(Instant.now().minus(Duration.ofDays(1))))
                : authorization;

        mvc.perform(json(post(REGISTER), registerBody("ana@example.com", PASSWORD))
                        .header(HttpHeaders.AUTHORIZATION, header))
                .andExpect(status().isCreated());
        mvc.perform(json(post(LOGIN), loginBody("ana@example.com", PASSWORD))
                        .header(HttpHeaders.AUTHORIZATION, header))
                .andExpect(status().isOk());
        mvc.perform(json(post(REFRESH), refreshBody("old-refresh"))
                        .header(HttpHeaders.AUTHORIZATION, header))
                .andExpect(status().isOk());
        mvc.perform(json(post(LOGOUT), refreshBody("old-refresh"))
                        .header(HttpHeaders.AUTHORIZATION, header))
                .andExpect(status().isNoContent());
    }

    @ParameterizedTest
    @ValueSource(strings = {"GET " + LOGIN, "GET " + REGISTER, "PUT " + REGISTER, "GET /api/v1/auth/me",
            "GET " + REFRESH, "GET " + LOGOUT, "PUT " + LOGOUT})
    void otherMethodsAndPathsUnderAuthAre404WithoutChallenge(String request) throws Exception {
        var parts = request.split(" ");
        var builder = parts[0].equals("GET") ? get(parts[1]) : put(parts[1]);

        mvc.perform(builder.header(HttpHeaders.AUTHORIZATION, "Bearer not-a-jwt"))
                .andExpect(status().isNotFound())
                .andExpect(header().doesNotExist(HttpHeaders.WWW_AUTHENTICATE))
                .andExpect(jsonPath("$.type").value("urn:snapledger:problem:not-found"));
        verifyNoInteractions(service);
    }

    // --- password reset ---
    // PT: --- redefinição de senha ---

    @Test
    void passwordResetRequestIs202WithAnEmptyBody() throws Exception {
        mvc.perform(fromNewIp(json(post(RESET), JSON.writeValueAsString(Map.of("email", "ana@example.com")))))
                .andExpect(status().isAccepted())
                .andExpect(content().string(""));

        verify(passwordReset).request("ana@example.com");
    }

    @ParameterizedTest
    @ValueSource(strings = {"{}", "{\"email\":null}", "{\"email\":\"not-an-email\"}", "{\"email\":\" ana@example.com\"}"})
    void passwordResetRequestWithABadEmailIs400(String body) throws Exception {
        mvc.perform(fromNewIp(json(post(RESET), body)))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.type").value("urn:snapledger:problem:validation-error"))
                .andExpect(jsonPath("$.errors[0].field").value("email"));
        verifyNoInteractions(passwordReset);
    }

    @Test
    void passwordResetVerifyIs200WithTheTokenAndNoStore() throws Exception {
        when(passwordReset.verify("ana@example.com", "042917"))
                .thenReturn(new IssuedToken("reset-token-value", Duration.ofMinutes(10)));

        var body = mvc.perform(fromNewIp(json(post(VERIFY), verifyBody("ana@example.com", "042917"))))
                .andExpect(status().isOk())
                .andExpect(header().string(HttpHeaders.CACHE_CONTROL, "no-store"))
                .andExpect(header().string(HttpHeaders.PRAGMA, "no-cache"))
                .andExpect(jsonPath("$.resetToken").value("reset-token-value"))
                .andExpect(jsonPath("$.expiresIn").value(600))
                .andReturn().getResponse().getContentAsString();

        assertThat(JSON.readTree(body).propertyNames()).containsExactlyInAnyOrder("resetToken", "expiresIn");
    }

    @Test
    void passwordResetVerifyWithAWrongCodeIs400InvalidCode() throws Exception {
        doThrow(new InvalidCodeException()).when(passwordReset).verify(any(), any());

        mvc.perform(fromNewIp(json(post(VERIFY), verifyBody("ana@example.com", "042917"))))
                .andExpect(status().isBadRequest())
                .andExpect(content().contentTypeCompatibleWith(MediaType.APPLICATION_PROBLEM_JSON))
                .andExpect(jsonPath("$.type").value("urn:snapledger:problem:invalid-code"))
                .andExpect(jsonPath("$.title").value("Invalid code"))
                .andExpect(jsonPath("$.instance").value(VERIFY));
    }

    @ParameterizedTest
    @ValueSource(strings = {"12345", "1234567", "12345a", "１２３４５６", "123456\n", " 123456", ""})
    void passwordResetVerifyValidatesTheCodeAndNeverEchoesIt(String code) throws Exception {
        var body = mvc.perform(fromNewIp(json(post(VERIFY), verifyBody("ana@example.com", code))))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.type").value("urn:snapledger:problem:validation-error"))
                .andExpect(jsonPath("$.errors[0].field").value("code"))
                .andReturn().getResponse().getContentAsString();

        if (!code.isBlank()) {
            assertThat(body).doesNotContain(code);
        }
        verifyNoInteractions(passwordReset);
    }

    @Test
    void passwordResetConfirmIs204WithAnEmptyBody() throws Exception {
        mvc.perform(fromNewIp(json(post(CONFIRM), confirmBody("reset-token-value", PASSWORD))))
                .andExpect(status().isNoContent())
                .andExpect(content().string(""));

        verify(passwordReset).confirm("reset-token-value", PASSWORD);
    }

    @Test
    void passwordResetConfirmWithABadTokenIs400InvalidResetToken() throws Exception {
        doThrow(new InvalidResetTokenException()).when(passwordReset).confirm(any(), any());

        mvc.perform(fromNewIp(json(post(CONFIRM), confirmBody("reset-token-value", PASSWORD))))
                .andExpect(status().isBadRequest())
                .andExpect(content().contentTypeCompatibleWith(MediaType.APPLICATION_PROBLEM_JSON))
                .andExpect(jsonPath("$.type").value("urn:snapledger:problem:invalid-reset-token"))
                .andExpect(jsonPath("$.title").value("Invalid reset token"))
                .andExpect(jsonPath("$.instance").value(CONFIRM));
    }

    @Test
    void passwordResetConfirmAppliesTheRegisterPasswordRulesAndNeverEchoesTheSecrets() throws Exception {
        var shortPassword = "x" + UUID.randomUUID().toString().substring(0, 5);

        var body = mvc.perform(fromNewIp(json(post(CONFIRM), confirmBody("reset-token-value", shortPassword))))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.errors[0].field").value("newPassword"))
                .andReturn().getResponse().getContentAsString();

        assertThat(body).doesNotContain(shortPassword).doesNotContain("reset-token-value");
        verifyNoInteractions(passwordReset);
    }

    @ParameterizedTest
    @ValueSource(strings = {"{}", "{\"resetToken\":\"\",\"newPassword\":\"long-enough-pw\"}"})
    void passwordResetConfirmWithoutATokenIs400Validation(String body) throws Exception {
        mvc.perform(fromNewIp(json(post(CONFIRM), body)))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.type").value("urn:snapledger:problem:validation-error"));
        verifyNoInteractions(passwordReset);
    }

    @ParameterizedTest
    @ValueSource(strings = {RESET, VERIFY, CONFIRM})
    void theIpLimitAnswers429WithRetryAfterAndNeverReachesTheService(String path) throws Exception {
        var ip = randomIp();
        when(passwordReset.verify(any(), any())).thenReturn(new IssuedToken("reset-token-value", Duration.ofMinutes(10)));
        var limit = switch (path) {
            case RESET -> limits.passwordResetPerIp();
            case VERIFY -> limits.passwordResetVerifyPerIp();
            default -> limits.passwordResetConfirmPerIp();
        };
        var body = switch (path) {
            case RESET -> JSON.writeValueAsString(Map.of("email", "ana@example.com"));
            case VERIFY -> verifyBody("ana@example.com", "042917");
            default -> confirmBody("reset-token-value", PASSWORD);
        };
        for (int i = 0; i < limit; i++) {
            mvc.perform(fromIp(json(post(path), body), ip)).andExpect(status().is2xxSuccessful());
        }

        mvc.perform(fromIp(json(post(path), body), ip))
                .andExpect(status().isTooManyRequests())
                .andExpect(content().contentTypeCompatibleWith(MediaType.APPLICATION_PROBLEM_JSON))
                .andExpect(jsonPath("$.type").value("urn:snapledger:problem:too-many-requests"))
                .andExpect(jsonPath("$.title").value("Too many requests"))
                .andExpect(header().string(HttpHeaders.RETRY_AFTER, "3600"));

        // Another address is not affected. PT: Outro endereço não é afetado.
        mvc.perform(fromNewIp(json(post(path), body))).andExpect(status().is2xxSuccessful());
    }

    @Test
    void theForwardedForHeaderDoesNotChangeTheLimitedAddress() throws Exception {
        var ip = randomIp();
        var body = JSON.writeValueAsString(Map.of("email", "ana@example.com"));
        for (int i = 0; i < limits.passwordResetPerIp(); i++) {
            mvc.perform(fromIp(json(post(RESET), body), ip).header("X-Forwarded-For", "203.0.113." + i))
                    .andExpect(status().isAccepted());
        }

        mvc.perform(fromIp(json(post(RESET), body), ip).header("X-Forwarded-For", "198.51.100.77"))
                .andExpect(status().isTooManyRequests());
    }

    @ParameterizedTest
    @ValueSource(strings = {"Bearer not-a-jwt", "expired"})
    void passwordResetEndpointsIgnoreTheAuthorizationHeader(String authorization) throws Exception {
        var header = authorization.equals("expired")
                ? TestTokens.bearer(TestTokens.valid(Instant.now().minus(Duration.ofDays(1))))
                : authorization;
        when(passwordReset.verify(any(), any())).thenReturn(new IssuedToken("reset-token-value", Duration.ofMinutes(10)));

        mvc.perform(fromNewIp(json(post(RESET), JSON.writeValueAsString(Map.of("email", "ana@example.com")))
                        .header(HttpHeaders.AUTHORIZATION, header)))
                .andExpect(status().isAccepted());
        mvc.perform(fromNewIp(json(post(VERIFY), verifyBody("ana@example.com", "042917"))
                        .header(HttpHeaders.AUTHORIZATION, header)))
                .andExpect(status().isOk());
        mvc.perform(fromNewIp(json(post(CONFIRM), confirmBody("reset-token-value", PASSWORD))
                        .header(HttpHeaders.AUTHORIZATION, header)))
                .andExpect(status().isNoContent());
    }

    @ParameterizedTest
    @ValueSource(strings = {RESET, VERIFY, CONFIRM})
    void getOnThePasswordResetPathsIs404WithoutChallenge(String path) throws Exception {
        mvc.perform(get(path))
                .andExpect(status().isNotFound())
                .andExpect(header().doesNotExist(HttpHeaders.WWW_AUTHENTICATE))
                .andExpect(jsonPath("$.type").value("urn:snapledger:problem:not-found"));
        verifyNoInteractions(passwordReset);
    }

    private static String verifyBody(String email, String code) {
        return JSON.writeValueAsString(Map.of("email", email, "code", code));
    }

    private static String confirmBody(String resetToken, String newPassword) {
        return JSON.writeValueAsString(Map.of("resetToken", resetToken, "newPassword", newPassword));
    }

    // Each test uses its own client address, so the in-memory limit of one test never leaks into another.
    // PT: Cada teste usa o próprio endereço de cliente, então o limite em memória de um teste nunca vaza para outro.
    private static String randomIp() {
        var random = ThreadLocalRandom.current();
        return "10." + random.nextInt(256) + "." + random.nextInt(256) + "." + random.nextInt(1, 255);
    }

    private static MockHttpServletRequestBuilder fromIp(MockHttpServletRequestBuilder request, String ip) {
        return request.with(r -> {
            r.setRemoteAddr(ip);
            return r;
        });
    }

    private static MockHttpServletRequestBuilder fromNewIp(MockHttpServletRequestBuilder request) {
        return fromIp(request, randomIp());
    }

    private static void assertExactShape(String body) {
        var tree = JSON.readTree(body);
        assertThat(tree.propertyNames()).containsExactlyInAnyOrder("user", "tokens");
        assertThat(tree.get("user").propertyNames())
                .containsExactlyInAnyOrder("id", "name", "email", "currency", "createdAt", "emailVerified");
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

    private static String refreshBody(String refreshToken) {
        return JSON.writeValueAsString(Map.of("refreshToken", refreshToken));
    }
}
