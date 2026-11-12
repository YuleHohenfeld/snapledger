package com.yulehohenfeld.snapledger.shared.error;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.jwt;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.sql.SQLException;
import java.time.YearMonth;
import java.util.Map;
import java.util.UUID;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Positive;
import jakarta.validation.constraints.Size;

import com.jayway.jsonpath.JsonPath;

import lombok.RequiredArgsConstructor;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.TestComponent;
import org.springframework.boot.test.system.CapturedOutput;
import org.springframework.boot.test.system.OutputCaptureExtension;
import org.springframework.boot.webmvc.test.autoconfigure.WebMvcTest;
import org.springframework.context.annotation.Import;
import org.springframework.dao.DataAccessResourceFailureException;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.AccessDeniedException;
import org.springframework.security.authentication.InsufficientAuthenticationException;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.validation.annotation.Validated;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import com.yulehohenfeld.snapledger.shared.config.ClockConfig;
import com.yulehohenfeld.snapledger.support.ImportSecurityStack;

/** Every error leaves the API as the contract's ProblemDetail, behind the real security config. */
@ExtendWith(OutputCaptureExtension.class)
@WebMvcTest(controllers = GlobalExceptionHandlerTest.ProbeController.class)
@ImportSecurityStack
@Import({ClockConfig.class, GlobalExceptionHandlerTest.ProbeController.class,
        GlobalExceptionHandlerTest.ProbeService.class})
class GlobalExceptionHandlerTest {

    static final String BASE = "/api/v1/probe";
    static final String EMAIL = "alice.secret@example.com";

    @Autowired
    MockMvc mvc;

    @Test
    void accessDeniedInsideMvcReachesTheSecurityLayerAsForbidden() throws Exception {
        mvc.perform(get(BASE + "/forbidden").with(jwt()))
                .andExpect(status().isForbidden())
                .andExpect(content().contentTypeCompatibleWith(MediaType.APPLICATION_PROBLEM_JSON))
                .andExpect(jsonPath("$.type").value("urn:snapledger:problem:forbidden"))
                .andExpect(jsonPath("$.title").value("Forbidden"))
                .andExpect(jsonPath("$.errorId").doesNotExist());
    }

    @Test
    void authenticationExceptionInsideMvcReachesTheSecurityLayerAsUnauthorized() throws Exception {
        mvc.perform(get(BASE + "/unauthenticated").with(jwt()))
                .andExpect(status().isUnauthorized())
                .andExpect(header().string(HttpHeaders.WWW_AUTHENTICATE, "Bearer"))
                .andExpect(jsonPath("$.type").value("urn:snapledger:problem:unauthorized"));
    }

    @Test
    void invalidRequestParameterIsValidationErrorNamingTheParameterButNotTheValue() throws Exception {
        var rejected = "much-too-long";

        var body = mvc.perform(get(BASE + "/search").param("q", rejected).with(jwt()))
                .andExpect(status().isBadRequest())
                .andExpect(content().contentTypeCompatibleWith(MediaType.APPLICATION_PROBLEM_JSON))
                .andExpect(jsonPath("$.type").value("urn:snapledger:problem:validation-error"))
                .andExpect(jsonPath("$.title").value("Validation failed"))
                .andExpect(jsonPath("$.errors.length()").value(1))
                .andExpect(jsonPath("$.errors[0].field").value("q"))
                .andExpect(jsonPath("$.errors[0].message").isNotEmpty())
                .andReturn().getResponse().getContentAsString();

        assertThat(body).doesNotContain(rejected);
    }

    @Test
    void serviceLevelConstraintViolationIsValidationErrorWithTheLastPathNode() throws Exception {
        var rejected = "TOOLONG";

        var body = mvc.perform(get(BASE + "/service-check").param("code", rejected).with(jwt()))
                .andExpect(status().isBadRequest())
                .andExpect(content().contentTypeCompatibleWith(MediaType.APPLICATION_PROBLEM_JSON))
                .andExpect(jsonPath("$.type").value("urn:snapledger:problem:validation-error"))
                .andExpect(jsonPath("$.errors.length()").value(1))
                .andExpect(jsonPath("$.errors[0].field").value("code"))
                .andExpect(jsonPath("$.errors[0].message").isNotEmpty())
                .andReturn().getResponse().getContentAsString();

        assertThat(body).doesNotContain(rejected);
    }

    // Spring falls back to application/problem+json for ProblemDetail bodies when the Accept
    // header excludes it, so the 406 itself never fails to render (and never becomes a 500).
    @ParameterizedTest
    @ValueSource(strings = {MediaType.APPLICATION_XML_VALUE, MediaType.TEXT_HTML_VALUE, MediaType.TEXT_PLAIN_VALUE})
    void notAcceptableIsProblemDetailEvenWhenTheClientDoesNotAcceptJson(String accept) throws Exception {
        mvc.perform(get(BASE + "/json").header(HttpHeaders.ACCEPT, accept).with(jwt()))
                .andExpect(status().isNotAcceptable())
                .andExpect(content().contentTypeCompatibleWith(MediaType.APPLICATION_PROBLEM_JSON))
                .andExpect(jsonPath("$.type").value("urn:snapledger:problem:not-acceptable"))
                .andExpect(jsonPath("$.title").value("Not acceptable"))
                .andExpect(jsonPath("$.status").value(406));
    }

    @Test
    void dataAccessErrorNeverLeaksColumnValuesToBodyOrLog(CapturedOutput output) throws Exception {
        var body = mvc.perform(get(BASE + "/duplicate").with(jwt()))
                .andExpect(status().isInternalServerError())
                .andExpect(jsonPath("$.type").value("urn:snapledger:problem:internal-error"))
                .andReturn().getResponse().getContentAsString();

        String errorId = JsonPath.read(body, "$.errorId");
        assertThat(body).doesNotContain(EMAIL).doesNotContain("uq_users_email");
        assertThat(output.getAll())
                .contains(errorId)
                .contains(DataIntegrityViolationException.class.getName())
                .contains("uq_users_email")
                .doesNotContain(EMAIL);
    }

    @Test
    void bareHibernateConstraintViolationIsLoggedMaskedLikeAnyDataAccessError(CapturedOutput output) throws Exception {
        var body = expectInternalError(BASE + "/hibernate-duplicate");

        String errorId = JsonPath.read(body, "$.errorId");
        assertThat(body).doesNotContain(EMAIL);
        assertThat(output.getAll())
                .contains(errorId)
                .contains(org.hibernate.exception.ConstraintViolationException.class.getName())
                .contains("constraint=uq_users_email")
                .doesNotContain(EMAIL);
    }

    @Test
    void sqlExceptionWrappedInANonDatabaseExceptionIsStillLoggedMasked(CapturedOutput output) throws Exception {
        var body = expectInternalError(BASE + "/wrapped-sql");

        String errorId = JsonPath.read(body, "$.errorId");
        assertThat(body).doesNotContain(EMAIL);
        assertThat(output.getAll())
                .contains(errorId)
                .contains("Unexpected data access error")
                .contains(RuntimeException.class.getName())
                .doesNotContain(EMAIL);
    }

    @Test
    void dataAccessErrorWithoutConstraintLogsNoConstraintAndNoMessage(CapturedOutput output) throws Exception {
        var body = expectInternalError(BASE + "/db-down");

        String errorId = JsonPath.read(body, "$.errorId");
        assertThat(output.getAll())
                .contains(errorId)
                .contains(DataAccessResourceFailureException.class.getName())
                .contains("constraint=null")
                .doesNotContain(ProbeController.INTERNAL_MESSAGE)
                .doesNotContain(EMAIL);
    }

    @Test
    void invalidServiceReturnValueIsInternalErrorNotValidationError() throws Exception {
        expectInternalError(BASE + "/service-bad-result");
    }

    @Test
    void invalidControllerReturnValueIsInternalErrorNotValidationError() throws Exception {
        expectInternalError(BASE + "/controller-bad-result");
    }

    @Test
    void apiExceptionBecomesProblemWithFixedTitleAndInstance() throws Exception {
        mvc.perform(get(BASE + "/missing").with(jwt()))
                .andExpect(status().isNotFound())
                .andExpect(content().contentTypeCompatibleWith(MediaType.APPLICATION_PROBLEM_JSON))
                .andExpect(jsonPath("$.type").value("urn:snapledger:problem:not-found"))
                .andExpect(jsonPath("$.title").value("Not found"))
                .andExpect(jsonPath("$.status").value(404))
                .andExpect(jsonPath("$.detail").value("Resource not found."))
                .andExpect(jsonPath("$.instance").value(BASE + "/missing"));
    }

    @Test
    void validationErrorsListFieldAndMessageButNeverTheRejectedValue() throws Exception {
        var rejected = "way-too-long-name";

        var body = mvc.perform(post(BASE + "/items").with(jwt())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"name\":\"" + rejected + "\",\"quantity\":-3}"))
                .andExpect(status().isBadRequest())
                .andExpect(content().contentTypeCompatibleWith(MediaType.APPLICATION_PROBLEM_JSON))
                .andExpect(jsonPath("$.type").value("urn:snapledger:problem:validation-error"))
                .andExpect(jsonPath("$.title").value("Validation failed"))
                .andExpect(jsonPath("$.instance").value(BASE + "/items"))
                .andExpect(jsonPath("$.errors.length()").value(2))
                .andExpect(jsonPath("$.errors[?(@.field == 'name')].message").exists())
                .andExpect(jsonPath("$.errors[?(@.field == 'quantity')].message").exists())
                .andReturn().getResponse().getContentAsString();

        assertThat(body).doesNotContain(rejected).doesNotContain("-3").doesNotContain("rejectedValue");
    }

    @Test
    void malformedJsonIsValidationError() throws Exception {
        mvc.perform(post(BASE + "/items").with(jwt())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"name\": "))
                .andExpect(status().isBadRequest())
                .andExpect(content().contentTypeCompatibleWith(MediaType.APPLICATION_PROBLEM_JSON))
                .andExpect(jsonPath("$.type").value("urn:snapledger:problem:validation-error"))
                .andExpect(jsonPath("$.title").value("Validation failed"))
                .andExpect(jsonPath("$.errors").doesNotExist());
    }

    @Test
    void malformedUuidIsValidationErrorThatDoesNotEchoTheValue() throws Exception {
        mvc.perform(get(BASE + "/items/not-a-uuid").with(jwt()))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.type").value("urn:snapledger:problem:validation-error"))
                .andExpect(jsonPath("$.detail").value("Invalid value for parameter 'id'."));
    }

    @Test
    void malformedMonthIsValidationError() throws Exception {
        mvc.perform(get(BASE + "/month").param("month", "2026-13").with(jwt()))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.type").value("urn:snapledger:problem:validation-error"))
                .andExpect(jsonPath("$.detail").value("Invalid value for parameter 'month'."));
    }

    @Test
    void missingRequiredParameterIsValidationError() throws Exception {
        mvc.perform(get(BASE + "/month").with(jwt()))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.type").value("urn:snapledger:problem:validation-error"))
                .andExpect(jsonPath("$.detail").value("Required parameter 'month' is missing."));
    }

    @Test
    void unknownRouteIsNotFound() throws Exception {
        mvc.perform(get("/api/v1/does-not-exist").with(jwt()))
                .andExpect(status().isNotFound())
                .andExpect(content().contentTypeCompatibleWith(MediaType.APPLICATION_PROBLEM_JSON))
                .andExpect(jsonPath("$.type").value("urn:snapledger:problem:not-found"))
                .andExpect(jsonPath("$.title").value("Not found"))
                .andExpect(jsonPath("$.instance").value("/api/v1/does-not-exist"));
    }

    @Test
    void unknownRouteForAnAnonymousCallerIsUnauthorizedSoRoutesCannotBeDiscovered() throws Exception {
        mvc.perform(get("/api/v1/does-not-exist"))
                .andExpect(status().isUnauthorized())
                .andExpect(header().string(HttpHeaders.WWW_AUTHENTICATE, "Bearer"))
                .andExpect(content().contentTypeCompatibleWith(MediaType.APPLICATION_PROBLEM_JSON))
                .andExpect(jsonPath("$.type").value("urn:snapledger:problem:unauthorized"));
    }

    @Test
    void wrongMethodIsMethodNotAllowedAndKeepsAllowHeader() throws Exception {
        mvc.perform(delete(BASE + "/items").with(jwt()))
                .andExpect(status().isMethodNotAllowed())
                .andExpect(header().exists(HttpHeaders.ALLOW))
                .andExpect(content().contentTypeCompatibleWith(MediaType.APPLICATION_PROBLEM_JSON))
                .andExpect(jsonPath("$.type").value("urn:snapledger:problem:method-not-allowed"))
                .andExpect(jsonPath("$.title").value("Method not allowed"));
    }

    @Test
    void nonJsonBodyIsUnsupportedMediaType() throws Exception {
        mvc.perform(post(BASE + "/items").with(jwt())
                        .contentType(MediaType.TEXT_PLAIN)
                        .content("name=x"))
                .andExpect(status().isUnsupportedMediaType())
                .andExpect(content().contentTypeCompatibleWith(MediaType.APPLICATION_PROBLEM_JSON))
                .andExpect(jsonPath("$.type").value("urn:snapledger:problem:unsupported-media-type"))
                .andExpect(jsonPath("$.title").value("Unsupported media type"));
    }

    @Test
    void unexpectedErrorHidesInternalsAndReturnsAnErrorIdThatIsLogged(CapturedOutput output) throws Exception {
        var body = mvc.perform(get(BASE + "/boom").with(jwt()))
                .andExpect(status().isInternalServerError())
                .andExpect(content().contentTypeCompatibleWith(MediaType.APPLICATION_PROBLEM_JSON))
                .andExpect(jsonPath("$.type").value("urn:snapledger:problem:internal-error"))
                .andExpect(jsonPath("$.title").value("Internal error"))
                .andExpect(jsonPath("$.detail").value("An unexpected error occurred."))
                .andReturn().getResponse().getContentAsString();

        String errorId = JsonPath.read(body, "$.errorId");
        assertThat(UUID.fromString(errorId)).isNotNull();
        assertThat(body)
                .doesNotContain("IllegalStateException")
                .doesNotContain(ProbeController.INTERNAL_MESSAGE)
                .doesNotContain("at com.");
        assertThat(output.getAll()).contains(errorId).contains(ProbeController.INTERNAL_MESSAGE);
    }

    /** Asserts the generic 500 body and returns it. */
    private String expectInternalError(String path) throws Exception {
        return mvc.perform(get(path).with(jwt()))
                .andExpect(status().isInternalServerError())
                .andExpect(content().contentTypeCompatibleWith(MediaType.APPLICATION_PROBLEM_JSON))
                .andExpect(jsonPath("$.type").value("urn:snapledger:problem:internal-error"))
                .andExpect(jsonPath("$.detail").value("An unexpected error occurred."))
                .andExpect(jsonPath("$.errorId").isNotEmpty())
                .andReturn().getResponse().getContentAsString();
    }

    record ProbeRequest(@NotBlank @Size(max = 5) String name, @NotNull @Positive Integer quantity) {
    }

    /** Stands in for a feature service validated with @Validated (method validation proxy). */
    @TestComponent
    @Validated
    static class ProbeService {

        void check(@Size(max = 3) String code) {
            // Reaching here means the code was valid.
        }

        @Size(max = 3)
        String badResult() {
            return "TOOLONG";
        }
    }

    @TestComponent // never picked up by component scans; registered only by @Import above
    @RestController
    @RequiredArgsConstructor
    static class ProbeController {

        static final String INTERNAL_MESSAGE = "select * from users failed on host db-internal";

        private final ProbeService service;

        @GetMapping(BASE + "/forbidden")
        void forbidden() {
            throw new AccessDeniedException("internal reason");
        }

        @GetMapping(BASE + "/unauthenticated")
        void unauthenticated() {
            throw new InsufficientAuthenticationException("internal reason");
        }

        @GetMapping(BASE + "/search")
        String search(@RequestParam("q") @Size(max = 5) String query) {
            return query;
        }

        @GetMapping(BASE + "/service-check")
        void serviceCheck(@RequestParam String code) {
            service.check(code);
        }

        @GetMapping(BASE + "/json")
        Map<String, String> json() {
            return Map.of("ok", "true");
        }

        @GetMapping(BASE + "/duplicate")
        void duplicate() {
            // Shaped like a real PostgreSQL unique violation surfaced through Hibernate and Spring.
            var sql = new SQLException("ERROR: duplicate key value violates unique constraint \"uq_users_email\""
                    + " Detail: Key (lower(email::text))=(" + EMAIL + ") already exists.", "23505");
            var hibernate = new org.hibernate.exception.ConstraintViolationException(
                    "could not execute statement [" + sql.getMessage() + "]", sql, "uq_users_email");
            throw new DataIntegrityViolationException("could not execute statement; " + sql.getMessage(), hibernate);
        }

        @GetMapping(BASE + "/hibernate-duplicate")
        void hibernateDuplicate() {
            // Not translated by Spring (no repository proxy in between), so no DataAccessException.
            var sql = new SQLException("Detail: Key (lower(email::text))=(" + EMAIL + ") already exists.", "23505");
            throw new org.hibernate.exception.ConstraintViolationException(
                    "could not execute statement [" + sql.getMessage() + "]", sql, "uq_users_email");
        }

        @GetMapping(BASE + "/wrapped-sql")
        void wrappedSql() {
            // RuntimeException(cause) copies cause.toString() into its own message.
            throw new RuntimeException(new SQLException("Key (email)=(" + EMAIL + ") already exists.", "23505"));
        }

        @GetMapping(BASE + "/db-down")
        void databaseDown() {
            throw new DataAccessResourceFailureException(INTERNAL_MESSAGE + " for " + EMAIL);
        }

        @GetMapping(BASE + "/service-bad-result")
        String serviceBadResult() {
            return service.badResult();
        }

        @GetMapping(BASE + "/controller-bad-result")
        @Size(max = 3)
        String controllerBadResult() {
            return "TOOLONG";
        }

        @GetMapping(BASE + "/missing")
        void missing() {
            throw new NotFoundException();
        }

        @PostMapping(BASE + "/items")
        ResponseEntity<Void> create(@Valid @RequestBody ProbeRequest request) {
            return ResponseEntity.noContent().build();
        }

        @GetMapping(BASE + "/items/{id}")
        String item(@PathVariable UUID id) {
            return id.toString();
        }

        @GetMapping(BASE + "/month")
        String month(@RequestParam YearMonth month) {
            return month.toString();
        }

        @GetMapping(BASE + "/boom")
        void boom() {
            throw new IllegalStateException(INTERNAL_MESSAGE);
        }
    }
}
