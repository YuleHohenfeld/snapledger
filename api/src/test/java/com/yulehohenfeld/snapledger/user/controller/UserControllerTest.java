package com.yulehohenfeld.snapledger.user.controller;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.jwt;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.time.Duration;
import java.time.Instant;
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

import tools.jackson.databind.json.JsonMapper;

import com.yulehohenfeld.snapledger.shared.config.ClockConfig;
import com.yulehohenfeld.snapledger.shared.error.InvalidCodeException;
import com.yulehohenfeld.snapledger.shared.error.TooManyRequestsException;
import com.yulehohenfeld.snapledger.shared.error.UnauthorizedException;
import com.yulehohenfeld.snapledger.support.ImportSecurityStack;
import com.yulehohenfeld.snapledger.support.TestTokens;
import com.yulehohenfeld.snapledger.user.dto.UserResponse;
import com.yulehohenfeld.snapledger.user.service.EmailVerificationService;
import com.yulehohenfeld.snapledger.user.service.UserService;

/**
 * The contract of {@code GET /users/me} behind the real security chains.
 *
 * <p>PT: O contrato de {@code GET /users/me} atrás das cadeias de segurança reais.
 */
@WebMvcTest(UserController.class)
@ImportSecurityStack
@Import(ClockConfig.class)
class UserControllerTest {

    static final String ME = "/api/v1/users/me";

    @Autowired
    MockMvc mvc;

    @MockitoBean
    UserService service;

    @MockitoBean
    EmailVerificationService verification;

    @Test
    void returnsTheProfileOfTheTokenSubjectWithExactlyTheContractFields() throws Exception {
        var userId = UUID.randomUUID();
        when(service.getCurrent(userId)).thenReturn(new UserResponse(userId, "Ana Souza", "ana@example.com", "BRL",
                Instant.parse("2026-11-10T14:03:22Z"), false));

        var body = mvc.perform(get(ME).with(jwt().jwt(j -> j.subject(userId.toString()))))
                .andExpect(status().isOk())
                .andExpect(content().contentType(MediaType.APPLICATION_JSON))
                .andExpect(jsonPath("$.id").value(userId.toString()))
                .andExpect(jsonPath("$.name").value("Ana Souza"))
                .andExpect(jsonPath("$.email").value("ana@example.com"))
                .andExpect(jsonPath("$.currency").value("BRL"))
                .andExpect(jsonPath("$.createdAt").value("2026-11-10T14:03:22Z"))
                .andExpect(jsonPath("$.emailVerified").value(false))
                .andReturn().getResponse().getContentAsString();

        assertThat(JsonMapper.builder().build().readTree(body).propertyNames())
                .containsExactlyInAnyOrder("id", "name", "email", "currency", "createdAt", "emailVerified");
    }

    // Contract: a valid token whose user is gone is 401 unauthorized with the Bearer challenge.
    // PT: Contrato: um token válido cujo usuário sumiu é 401 unauthorized com o desafio Bearer.
    @Test
    void deletedUserIs401UnauthorizedWithBearerChallenge() throws Exception {
        var userId = UUID.randomUUID();
        when(service.getCurrent(userId)).thenThrow(new UnauthorizedException());

        mvc.perform(get(ME).with(jwt().jwt(j -> j.subject(userId.toString()))))
                .andExpect(status().isUnauthorized())
                .andExpect(header().string(HttpHeaders.WWW_AUTHENTICATE, "Bearer"))
                .andExpect(content().contentTypeCompatibleWith(MediaType.APPLICATION_PROBLEM_JSON))
                .andExpect(jsonPath("$.type").value("urn:snapledger:problem:unauthorized"))
                .andExpect(jsonPath("$.instance").value(ME));
    }

    @Test
    void missingTokenIs401() throws Exception {
        mvc.perform(get(ME))
                .andExpect(status().isUnauthorized())
                .andExpect(header().string(HttpHeaders.WWW_AUTHENTICATE, "Bearer"));
        verifyNoInteractions(service);
    }

    // The header that /auth/* ignores is still rejected here (ADR 0005).
    // PT: O header que o /auth/* ignora continua sendo recusado aqui (ADR 0005).
    @Test
    void garbageOrExpiredTokenIs401() throws Exception {
        mvc.perform(get(ME).header(HttpHeaders.AUTHORIZATION, "Bearer not-a-jwt"))
                .andExpect(status().isUnauthorized())
                .andExpect(jsonPath("$.type").value("urn:snapledger:problem:unauthorized"));
        var expired = TestTokens.valid(Instant.now().minus(Duration.ofDays(1)));
        mvc.perform(get(ME).header(HttpHeaders.AUTHORIZATION, TestTokens.bearer(expired)))
                .andExpect(status().isUnauthorized());
        verifyNoInteractions(service);
    }

    // --- email verification ---
    // PT: --- verificação de email ---

    static final String VERIFY = ME + "/email-verification";
    static final String VERIFY_CONFIRM = VERIFY + "/confirm";

    @Test
    void sendingTheCodeIs202WithAnEmptyBodyForTheTokenSubject() throws Exception {
        var userId = UUID.randomUUID();

        mvc.perform(post(VERIFY).with(jwt().jwt(j -> j.subject(userId.toString()))))
                .andExpect(status().isAccepted())
                .andExpect(content().string(""));

        verify(verification).send(userId);
    }

    @Test
    void aThrottledSendIs429WithRetryAfter() throws Exception {
        var userId = UUID.randomUUID();
        doThrow(new TooManyRequestsException(Duration.ofSeconds(60))).when(verification).send(userId);

        mvc.perform(post(VERIFY).with(jwt().jwt(j -> j.subject(userId.toString()))))
                .andExpect(status().isTooManyRequests())
                .andExpect(header().string(HttpHeaders.RETRY_AFTER, "60"))
                .andExpect(jsonPath("$.type").value("urn:snapledger:problem:too-many-requests"));
    }

    @Test
    void confirmingReturnsTheProfileWithEmailVerified() throws Exception {
        var userId = UUID.randomUUID();
        when(verification.confirm(userId, "042917")).thenReturn(new UserResponse(userId, "Ana Souza",
                "ana@example.com", "BRL", Instant.parse("2026-11-10T14:03:22Z"), true));

        mvc.perform(post(VERIFY_CONFIRM).with(jwt().jwt(j -> j.subject(userId.toString())))
                        .contentType(MediaType.APPLICATION_JSON).content("{\"code\":\"042917\"}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.id").value(userId.toString()))
                .andExpect(jsonPath("$.emailVerified").value(true));
    }

    @Test
    void aWrongCodeIs400InvalidCode() throws Exception {
        var userId = UUID.randomUUID();
        when(verification.confirm(userId, "042917")).thenThrow(new InvalidCodeException());

        mvc.perform(post(VERIFY_CONFIRM).with(jwt().jwt(j -> j.subject(userId.toString())))
                        .contentType(MediaType.APPLICATION_JSON).content("{\"code\":\"042917\"}"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.type").value("urn:snapledger:problem:invalid-code"));
    }

    @ParameterizedTest
    @ValueSource(strings = {"{}", "{\"code\":null}", "{\"code\":\"12345\"}", "{\"code\":\"１２３４５６\"}", "{\"code\":\"12345a\"}"})
    void aMalformedCodeIs400ValidationErrorAndNeverReachesTheService(String body) throws Exception {
        mvc.perform(post(VERIFY_CONFIRM).with(jwt().jwt(j -> j.subject(UUID.randomUUID().toString())))
                        .contentType(MediaType.APPLICATION_JSON).content(body))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.type").value("urn:snapledger:problem:validation-error"))
                .andExpect(jsonPath("$.errors[0].field").value("code"));
        verifyNoInteractions(verification);
    }

    @ParameterizedTest
    @ValueSource(strings = {VERIFY, VERIFY_CONFIRM})
    void bothEndpointsNeedAToken(String path) throws Exception {
        mvc.perform(post(path).contentType(MediaType.APPLICATION_JSON).content("{\"code\":\"042917\"}"))
                .andExpect(status().isUnauthorized())
                .andExpect(header().string(HttpHeaders.WWW_AUTHENTICATE, "Bearer"));
        verifyNoInteractions(verification);
    }

    @ParameterizedTest
    @ValueSource(strings = {VERIFY, VERIFY_CONFIRM})
    void getOnTheVerificationPathsIs405(String path) throws Exception {
        mvc.perform(get(path).with(jwt().jwt(j -> j.subject(UUID.randomUUID().toString()))))
                .andExpect(status().isMethodNotAllowed());
        verifyNoInteractions(verification);
    }
}
