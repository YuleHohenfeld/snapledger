package com.yulehohenfeld.snapledger.shared.error;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.jwt;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.request;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.sql.SQLException;
import java.util.UUID;

import jakarta.servlet.DispatcherType;
import jakarta.servlet.RequestDispatcher;

import com.jayway.jsonpath.JsonPath;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.CsvSource;
import org.junit.jupiter.params.provider.ValueSource;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.system.CapturedOutput;
import org.springframework.boot.test.system.OutputCaptureExtension;
import org.springframework.boot.webmvc.test.autoconfigure.WebMvcTest;
import org.springframework.context.annotation.Import;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpMethod;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.ResultActions;
import org.springframework.test.web.servlet.request.MockHttpServletRequestBuilder;

import com.yulehohenfeld.snapledger.shared.config.ClockConfig;
import com.yulehohenfeld.snapledger.support.ImportSecurityStack;

/**
 * /error as the container calls it (ADR 0007). MockMvc never performs an error dispatch, so each
 * test builds one by hand: dispatcher type ERROR plus the request attributes the container sets.
 * Callers are anonymous unless stated, which also proves chain 2 lets the ERROR dispatch through.
 *
 * <p>PT: O /error do jeito que o container o chama (ADR 0007). O MockMvc nunca faz um error
 * dispatch, então cada teste monta um à mão: dispatcher type ERROR mais os atributos de requisição
 * que o container define. Os chamadores são anônimos, salvo indicação, o que também prova que a
 * cadeia 2 deixa passar o dispatch ERROR.
 */
@ExtendWith(OutputCaptureExtension.class)
@WebMvcTest(ProblemErrorController.class)
@ImportSecurityStack
@Import(ClockConfig.class)
class ProblemErrorControllerTest {

    static final String ORIGINAL = "/api/v1/expenses";
    static final String EMAIL = "carol.secret@example.com";

    @Autowired
    MockMvc mvc;

    @ParameterizedTest
    @CsvSource({
            "400, validation-error, Validation failed",
            "404, not-found, Not found",
            "405, method-not-allowed, Method not allowed",
            "406, not-acceptable, Not acceptable",
            "415, unsupported-media-type, Unsupported media type"})
    void statusWithAContractSlugUsesIt(int status, String slug, String title) throws Exception {
        expectProblem(mvc.perform(errorDispatch(HttpMethod.GET, status)), status)
                .andExpect(jsonPath("$.type").value("urn:snapledger:problem:" + slug))
                .andExpect(jsonPath("$.title").value(title))
                .andExpect(jsonPath("$.detail").isNotEmpty())
                .andExpect(jsonPath("$.errorId").doesNotExist());
    }

    @ParameterizedTest
    @CsvSource({"413, Content Too Large", "414, URI Too Long", "431, Request Header Fields Too Large"})
    void statusWithoutASlugIsAboutBlankWithTheReasonPhrase(int status, String reason) throws Exception {
        expectProblem(mvc.perform(errorDispatch(HttpMethod.GET, status)), status)
                .andExpect(jsonPath("$.type").value("about:blank"))
                .andExpect(jsonPath("$.title").value(reason))
                .andExpect(jsonPath("$.errorId").doesNotExist());
    }

    @ParameterizedTest
    @ValueSource(ints = {500, 503})
    void serverErrorIsInternalErrorWithAnErrorIdThatIsLogged(int status, CapturedOutput output) throws Exception {
        var body = expectProblem(mvc.perform(errorDispatch(HttpMethod.GET, status)
                        .requestAttr(RequestDispatcher.ERROR_EXCEPTION, new IllegalStateException("internal detail"))), 500)
                .andExpect(jsonPath("$.type").value("urn:snapledger:problem:internal-error"))
                .andExpect(jsonPath("$.detail").value("An unexpected error occurred."))
                .andReturn().getResponse().getContentAsString();

        String errorId = JsonPath.read(body, "$.errorId");
        assertThat(UUID.fromString(errorId)).isNotNull();
        assertThat(body).doesNotContain("internal detail").doesNotContain("IllegalStateException");
        assertThat(output.getAll()).contains(errorId).contains("internal detail");
    }

    @Test
    void serverErrorWithoutAnExceptionAttributeIsStillInternalError() throws Exception {
        expectProblem(mvc.perform(errorDispatch(HttpMethod.GET, 500)), 500)
                .andExpect(jsonPath("$.type").value("urn:snapledger:problem:internal-error"))
                .andExpect(jsonPath("$.errorId").isNotEmpty());
    }

    @Test
    void databaseExceptionOfAServerErrorIsLoggedMasked(CapturedOutput output) throws Exception {
        var failure = new RuntimeException("wrapper",
                new SQLException("Key (email)=(" + EMAIL + ") already exists.", "23505"));

        var body = expectProblem(mvc.perform(errorDispatch(HttpMethod.GET, 500)
                        .requestAttr(RequestDispatcher.ERROR_EXCEPTION, failure)), 500)
                .andReturn().getResponse().getContentAsString();

        String errorId = JsonPath.read(body, "$.errorId");
        assertThat(body).doesNotContain(EMAIL);
        assertThat(output.getAll()).contains("Unexpected data access error errorId=" + errorId)
                .doesNotContain(EMAIL);
    }

    @Test
    void exceptionAttributeThatIsNotAThrowableIsIgnored() throws Exception {
        expectProblem(mvc.perform(errorDispatch(HttpMethod.GET, 500)
                        .requestAttr(RequestDispatcher.ERROR_EXCEPTION, "not an exception")), 500)
                .andExpect(jsonPath("$.type").value("urn:snapledger:problem:internal-error"));
    }

    @ParameterizedTest
    @ValueSource(strings = {"POST", "PUT", "PATCH", "DELETE", "OPTIONS"})
    void everyHttpMethodIsAnswered(String method) throws Exception {
        expectProblem(mvc.perform(errorDispatch(HttpMethod.valueOf(method), 400)), 400)
                .andExpect(jsonPath("$.type").value("urn:snapledger:problem:validation-error"));
    }

    @Test
    void htmlAcceptHeaderStillGetsProblemJson() throws Exception {
        expectProblem(mvc.perform(errorDispatch(HttpMethod.GET, 404)
                        .header(HttpHeaders.ACCEPT, MediaType.TEXT_HTML_VALUE)), 404)
                .andExpect(jsonPath("$.type").value("urn:snapledger:problem:not-found"));
    }

    @Test
    void instanceIsTheOriginalPathWithoutTheQueryString() throws Exception {
        mvc.perform(errorDispatch(HttpMethod.GET, 400)
                        .requestAttr(RequestDispatcher.ERROR_REQUEST_URI, ORIGINAL + "?email=" + EMAIL))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.instance").value(ORIGINAL));
    }

    @Test
    void missingStatusIsNotFound() throws Exception {
        expectProblem(mvc.perform(errorDispatch(HttpMethod.GET)), 404)
                .andExpect(jsonPath("$.type").value("urn:snapledger:problem:not-found"));
    }

    // 401 and 403 have contract slugs, but /error never asks for a token: WWW-Authenticate is
    // only sent by the security entry point (expectProblem asserts it is absent).
    // PT: 401 e 403 têm slugs no contrato, mas o /error nunca pede token: o WWW-Authenticate só é
    //     enviado pelo entry point de segurança (o expectProblem confere que ele não existe).
    @ParameterizedTest
    @CsvSource({"401, unauthorized, Unauthorized", "403, forbidden, Forbidden"})
    void authStatusUsesItsSlugWithoutAskingForAToken(int status, String slug, String title) throws Exception {
        expectProblem(mvc.perform(errorDispatch(HttpMethod.GET, status)), status)
                .andExpect(jsonPath("$.type").value("urn:snapledger:problem:" + slug))
                .andExpect(jsonPath("$.title").value(title));
    }

    @ParameterizedTest
    @ValueSource(ints = {400, 413, 500})
    void responseIsNeverSniffedNorCached(int status) throws Exception {
        mvc.perform(errorDispatch(HttpMethod.GET, status))
                .andExpect(header().string(ProblemErrorController.X_CONTENT_TYPE_OPTIONS, "nosniff"))
                .andExpect(header().string(HttpHeaders.CACHE_CONTROL, "no-store"));
    }

    @ParameterizedTest
    @ValueSource(strings = {"500", "garbage"})
    void statusThatIsNotAnIntegerIsNotFound(String garbage) throws Exception {
        expectProblem(mvc.perform(errorDispatch(HttpMethod.GET, 500)
                        .requestAttr(RequestDispatcher.ERROR_STATUS_CODE, garbage)), 404)
                .andExpect(jsonPath("$.type").value("urn:snapledger:problem:not-found"));
    }

    @ParameterizedTest
    @ValueSource(ints = {-1, 99, 200, 302, 600, 1000})
    void statusOutsideTheErrorRangeIsNotFound(int status) throws Exception {
        expectProblem(mvc.perform(errorDispatch(HttpMethod.GET, status)), 404)
                .andExpect(jsonPath("$.type").value("urn:snapledger:problem:not-found"));
    }

    @Test
    void directCallByAnAnonymousClientIsUnauthorized() throws Exception {
        // A REQUEST dispatch: only the container can make an ERROR one.
        // PT: Um dispatch REQUEST: só o container consegue fazer um ERROR.
        mvc.perform(get("/error"))
                .andExpect(status().isUnauthorized())
                .andExpect(jsonPath("$.type").value("urn:snapledger:problem:unauthorized"));
    }

    @Test
    void directCallByAnAuthenticatedClientIsNotFound() throws Exception {
        expectProblem(mvc.perform(get("/error").with(jwt())), 404)
                .andExpect(jsonPath("$.type").value("urn:snapledger:problem:not-found"))
                .andExpect(jsonPath("$.instance").value("/error"));
    }

    /**
     * What the container does when it forwards a failed request to /error.
     *
     * <p>PT: O que o container faz quando encaminha uma requisição que falhou para /error.
     */
    private static MockHttpServletRequestBuilder errorDispatch(HttpMethod method, int status) {
        return errorDispatch(method).requestAttr(RequestDispatcher.ERROR_STATUS_CODE, status);
    }

    /**
     * An error dispatch without the status attribute.
     *
     * <p>PT: Um error dispatch sem o atributo de status.
     */
    private static MockHttpServletRequestBuilder errorDispatch(HttpMethod method) {
        return request(method, "/error")
                .requestAttr(RequestDispatcher.ERROR_REQUEST_URI, ORIGINAL)
                .with(r -> {
                    r.setDispatcherType(DispatcherType.ERROR);
                    return r;
                });
    }

    private static ResultActions expectProblem(ResultActions result, int status) throws Exception {
        return result.andExpect(status().is(status))
                .andExpect(content().contentTypeCompatibleWith(MediaType.APPLICATION_PROBLEM_JSON))
                .andExpect(header().doesNotExist(HttpHeaders.WWW_AUTHENTICATE))
                .andExpect(jsonPath("$.status").value(status));
    }
}
