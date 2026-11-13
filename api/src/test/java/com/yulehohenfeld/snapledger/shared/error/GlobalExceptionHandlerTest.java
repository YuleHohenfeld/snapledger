package com.yulehohenfeld.snapledger.shared.error;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.jwt;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.net.SocketException;
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

import org.apache.catalina.connector.ClientAbortException;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.logging.LogLevel;
import org.springframework.boot.logging.LoggingSystem;
import org.springframework.boot.test.context.TestComponent;
import org.springframework.boot.test.system.CapturedOutput;
import org.springframework.boot.test.system.OutputCaptureExtension;
import org.springframework.boot.webmvc.test.autoconfigure.WebMvcTest;
import org.springframework.context.annotation.Import;
import org.springframework.dao.DataAccessResourceFailureException;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.http.converter.HttpMessageNotWritableException;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.mock.web.MockHttpServletResponse;
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
import org.springframework.web.context.request.ServletWebRequest;
import org.springframework.web.multipart.MaxUploadSizeExceededException;
import org.springframework.web.servlet.mvc.method.annotation.ExceptionHandlerExceptionResolver;
import org.springframework.web.servlet.mvc.support.DefaultHandlerExceptionResolver;

import com.yulehohenfeld.snapledger.shared.config.ClockConfig;
import com.yulehohenfeld.snapledger.support.ImportSecurityStack;

/**
 * Every error leaves the API as the contract's ProblemDetail, behind the real security config.
 *
 * <p>PT: Todo erro sai da API como o ProblemDetail do contrato, atrás da configuração de segurança
 * real.
 */
@ExtendWith(OutputCaptureExtension.class)
@WebMvcTest(controllers = GlobalExceptionHandlerTest.ProbeController.class)
@ImportSecurityStack
@Import({ClockConfig.class, GlobalExceptionHandlerTest.ProbeController.class,
        GlobalExceptionHandlerTest.ProbeService.class})
class GlobalExceptionHandlerTest {

    static final String BASE = "/api/v1/probe";
    static final String EMAIL = "alice.secret@example.com";
    static final String SPRING_WEB = "org.springframework.web";
    static final String RESOLVER_LOGGER = ExceptionHandlerExceptionResolver.class.getName();
    static final String DEFAULT_RESOLVER_LOGGER = DefaultHandlerExceptionResolver.class.getName();
    static final String FORGED_LINE = "ERROR forged-admin-login-succeeded";

    @Autowired
    MockMvc mvc;

    @Autowired
    GlobalExceptionHandler handler;

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
    // PT: O Spring volta para application/problem+json em corpos ProblemDetail quando o header
    //     Accept o exclui, então o próprio 406 nunca falha ao ser gerado (e nunca vira um 500).
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
        assertThat(body).doesNotContain(EMAIL).doesNotContain("uk_users_email");
        assertThat(output.getAll())
                .contains(errorId)
                .contains(DataIntegrityViolationException.class.getName())
                .contains("uk_users_email")
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
                .contains("constraint=uk_users_email")
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
    void databaseErrorAttachedAsSuppressedIsLoggedMaskedAndNeverInTheBody(CapturedOutput output) throws Exception {
        var body = expectInternalError(BASE + "/suppressed-sql");

        String errorId = JsonPath.read(body, "$.errorId");
        assertThat(body).doesNotContain(EMAIL);
        assertThat(output.getAll())
                .contains(errorId)
                .contains("Unexpected data access error")
                .contains(IllegalStateException.class.getName())
                .doesNotContain(EMAIL);
    }

    // Spring MVC wraps an Error thrown by a handler in a ServletException and hands it to the
    // exception resolvers, so it is answered here and never reaches the container's /error.
    // PT: O Spring MVC embrulha um Error lançado por um handler numa ServletException e a entrega
    //     aos exception resolvers, então ele é respondido aqui e nunca chega ao /error do container.
    @Test
    void errorThrownByAControllerIsInternalErrorAndItsDatabaseCauseIsMasked(CapturedOutput output) throws Exception {
        var body = expectInternalError(BASE + "/jvm-error");

        String errorId = JsonPath.read(body, "$.errorId");
        assertThat(body).doesNotContain(EMAIL).doesNotContain("AssertionError");
        assertThat(output.getAll())
                .contains(errorId)
                .contains("Unexpected data access error")
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

    // A client that reset the connection while the body was read: nobody is left to read a body,
    // so nothing is written and nothing reaches ERROR (the DEBUG line is in InternalErrorsTest).
    // The status is still 500: the default 200 would record a success that never happened.
    // PT: Um cliente que resetou a conexão enquanto o corpo era lido: não sobrou ninguém para ler
    //     um corpo, então nada é escrito e nada chega a ERROR (a linha DEBUG está no
    //     InternalErrorsTest). O status ainda é 500: o 200 padrão registraria um sucesso que nunca
    //     aconteceu.
    @Test
    void clientAbortIsHandledWithoutABodyAndWithoutAnErrorLine(CapturedOutput output) throws Exception {
        var response = mvc.perform(get(BASE + "/client-abort").with(jwt())).andReturn().getResponse();

        assertThat(response.getStatus()).isEqualTo(500);
        assertThat(response.getContentAsString()).isEmpty();
        assertThat(output.getAll()).doesNotContain("errorId=").doesNotContain("\tat ");
    }

    @Test
    void frameworkServerErrorCausedByAClientAbortGetsNoBody(CapturedOutput output) {
        var failure = new HttpMessageNotWritableException("could not write",
                new ClientAbortException(new SocketException("Connection reset")));
        var response = new MockHttpServletResponse();

        var result = handler.handleExceptionInternal(failure, null, new HttpHeaders(),
                HttpStatus.INTERNAL_SERVER_ERROR, servletRequest(response));

        assertThat(result).isNull();
        assertThat(response.getStatus()).isEqualTo(500);
        assertThat(output.getAll()).doesNotContain("errorId=");
    }

    // After commit the base class would log "Response already committed. Ignoring: " + the
    // exception's toString, unmasked, next to our own line. Now it is one masked line. Not
    // rethrown: DefaultHandlerExceptionResolver would resolve it with unmasked WARNs (see
    // handleExceptionInternal and ContainerErrorDispatchIntegrationTest).
    // PT: Depois do envio, a classe base registraria "Response already committed. Ignoring: " + o
    //     toString da exceção, sem máscara, ao lado da nossa linha. Agora é uma linha mascarada.
    //     Não é relançada: o DefaultHandlerExceptionResolver a resolveria com WARNs sem máscara (veja
    //     o handleExceptionInternal e o ContainerErrorDispatchIntegrationTest).
    @Test
    void frameworkErrorAfterCommitIsOneMaskedLineWithoutTheBaseClassWarning(CapturedOutput output) {
        var failure = new HttpMessageNotWritableException("could not write " + EMAIL,
                new DataIntegrityViolationException("Key (email)=(" + EMAIL + ") already exists."));

        var result = handler.handleExceptionInternal(failure, null, new HttpHeaders(),
                HttpStatus.INTERNAL_SERVER_ERROR, servletRequest(committedResponse()));

        assertThat(result).isNull();
        assertThat(output.getAll())
                .containsOnlyOnce("errorId=")
                .contains("Unexpected data access error errorId=")
                .contains("responseCommitted=true")
                .doesNotContain("Response already committed")
                .doesNotContain(EMAIL);
    }

    @Test
    void unexpectedErrorAfterCommitIsRethrownUnloggedAndWritesNothing(CapturedOutput output) {
        var response = committedResponse();
        var failure = new IllegalStateException("broken after commit");

        assertThatThrownBy(() -> handler.handleUnexpected(failure, new MockHttpServletRequest(), response))
                .isSameAs(failure);
        assertThat(response.getContentAsByteArray()).isEmpty();
        assertThat(output.getAll()).doesNotContain("errorId=");
    }

    // A disconnect after commit is not rethrown: nobody is left to see an abort, so it stays the
    // one DEBUG line (silent at the default INFO level) and is handled here.
    // PT: Uma desconexão depois do envio não é relançada: não sobrou ninguém para ver um aborto,
    //     então continua a única linha DEBUG (calada no nível padrão INFO) e é tratada aqui.
    @Test
    void clientAbortAfterCommitIsHandledWithoutAnErrorLine(CapturedOutput output) throws Exception {
        var response = committedResponse();

        var result = handler.handleUnexpected(new ClientAbortException(new SocketException("Connection reset")),
                new MockHttpServletRequest(), response);

        assertThat(result).isNull();
        assertThat(response.getContentAsByteArray()).isEmpty();
        assertThat(output.getAll()).doesNotContain("errorId=").doesNotContain("\tat ");
    }

    // A framework status without a contract slug gets the same about:blank body as at /error
    // (ProblemFactory.forFrameworkStatus), not Spring's own ProblemDetail.
    // PT: Um status do framework sem slug no contrato recebe o mesmo corpo about:blank do /error
    //     (ProblemFactory.forFrameworkStatus), e não o ProblemDetail do próprio Spring.
    @Test
    void frameworkStatusWithoutASlugIsAboutBlankWithTheReasonPhrase() throws Exception {
        mvc.perform(get(BASE + "/too-large").with(jwt()))
                .andExpect(status().is(413))
                .andExpect(content().contentTypeCompatibleWith(MediaType.APPLICATION_PROBLEM_JSON))
                .andExpect(jsonPath("$.type").value("about:blank"))
                .andExpect(jsonPath("$.title").value("Content Too Large"))
                .andExpect(jsonPath("$.status").value(413))
                .andExpect(jsonPath("$.detail").doesNotExist())
                .andExpect(jsonPath("$.instance").value(BASE + "/too-large"));
    }

    /**
     * With Spring's web logging at DEBUG (a common troubleshooting setting), the resolver that runs
     * our handler logs "Resolved [" + the exception's toString + "]" for every exception it
     * resolves, unmasked. logback-spring.xml pins that logger to INFO, so the database value stays
     * out of the log even then.
     *
     * <p>PT: Com o log web do Spring em DEBUG (uma configuração comum para investigar problemas), o
     * resolver que executa o nosso handler registra "Resolved [" + o toString da exceção + "]" para
     * toda exceção que ele resolve, sem máscara. O logback-spring.xml fixa esse logger em INFO, então
     * o valor do banco fica fora do log mesmo assim.
     */
    @Test
    void springWebDebugLoggingDoesNotPrintTheResolvedExceptionUnmasked(CapturedOutput output) throws Exception {
        withLogLevel(SPRING_WEB, LogLevel.DEBUG, () -> expectInternalError(BASE + "/duplicate"));

        assertThat(output.getAll())
                .contains("Unexpected data access error errorId=")
                .doesNotContain("Resolved [")
                .doesNotContain(EMAIL);
    }

    // Positive control: with the resolver's own logger at DEBUG the same request prints the value,
    // so the test above passes because of the pin and the logger name is the one Spring uses.
    // PT: Controle positivo: com o próprio logger do resolver em DEBUG, a mesma requisição imprime
    //     o valor, então o teste acima passa por causa da fixação e o nome do logger é o que o Spring
    //     usa.
    @Test
    void resolverLoggerAtDebugWouldPrintTheValue(CapturedOutput output) throws Exception {
        withLogLevel(RESOLVER_LOGGER, LogLevel.DEBUG, () -> expectInternalError(BASE + "/duplicate"));

        assertThat(output.getAll()).contains("Resolved [").contains(EMAIL);
    }

    /**
     * Spring's fallback resolver gets an exception only when one of our handlers failed. With the
     * response already committed it would log, at WARN, the exception's toString unmasked and
     * with its raw newline (log forging). logback-spring.xml pins it to ERROR, so neither the
     * value nor the forged line reaches the log.
     *
     * <p>PT: O resolver reserva do Spring só recebe uma exceção quando um dos nossos handlers
     * falhou. Com a resposta já enviada, ele registraria em WARN o toString da exceção sem máscara
     * e com a quebra de linha crua (forja de log). O logback-spring.xml o fixa em ERROR, então nem o
     * valor nem a linha forjada chegam ao log.
     */
    @Test
    void defaultResolverDoesNotPrintACommittedFailureUnmasked(CapturedOutput output) {
        var handled = resolveWithDefaultResolver();

        assertThat(handled).isTrue();
        assertThat(output.getAll())
                .doesNotContain("Ignoring exception, response committed already")
                .doesNotContain(EMAIL)
                .doesNotContain(FORGED_LINE);
    }

    // Positive control: with the resolver's own logger back at WARN the same call prints the value
    // and the forged line, so the test above passes because of the pin, under the name Spring uses.
    // PT: Controle positivo: com o próprio logger do resolver de volta em WARN, a mesma chamada
    //     imprime o valor e a linha forjada, então o teste acima passa por causa da fixação, com o
    //     nome que o Spring usa.
    @Test
    void defaultResolverLoggerAtWarnWouldPrintTheValue(CapturedOutput output) throws Exception {
        withLogLevel(DEFAULT_RESOLVER_LOGGER, LogLevel.WARN, GlobalExceptionHandlerTest::resolveWithDefaultResolver);

        assertThat(output.getAll())
                .contains("Ignoring exception, response committed already")
                .contains(EMAIL)
                .contains("\n" + FORGED_LINE);
    }

    /**
     * A framework error whose message carries a value and a newline, resolved by a plain
     * DefaultHandlerExceptionResolver against a committed response.
     *
     * <p>PT: Um erro do framework cuja mensagem carrega um valor e uma quebra de linha, resolvido
     * por um DefaultHandlerExceptionResolver puro contra uma resposta já enviada.
     */
    private static boolean resolveWithDefaultResolver() {
        var failure = new HttpMessageNotWritableException("could not write " + EMAIL + "\n" + FORGED_LINE);
        var result = new DefaultHandlerExceptionResolver()
                .resolveException(new MockHttpServletRequest(), committedResponse(), null, failure);
        return result != null;
    }

    /**
     * Runs the action with {@code name} at {@code level}, then puts back the level logback-spring.xml
     * gives it (null = inherited), so later tests see the real configuration.
     *
     * <p>PT: Executa a ação com {@code name} em {@code level} e depois devolve o nível que o
     * logback-spring.xml dá a ele (null = herdado), para que os testes seguintes vejam a configuração
     * real.
     */
    private static void withLogLevel(String name, LogLevel level, ThrowingAction action) throws Exception {
        var logging = LoggingSystem.get(GlobalExceptionHandlerTest.class.getClassLoader());
        var configured = logging.getLoggerConfiguration(name).getConfiguredLevel();
        logging.setLogLevel(name, level);
        try {
            action.run();
        } finally {
            logging.setLogLevel(name, configured);
        }
    }

    @FunctionalInterface
    interface ThrowingAction {
        void run() throws Exception;
    }

    /**
     * Asserts the generic 500 body and returns it.
     *
     * <p>PT: Confere o corpo 500 genérico e o devolve.
     */
    private String expectInternalError(String path) throws Exception {
        return mvc.perform(get(path).with(jwt()))
                .andExpect(status().isInternalServerError())
                .andExpect(content().contentTypeCompatibleWith(MediaType.APPLICATION_PROBLEM_JSON))
                .andExpect(jsonPath("$.type").value("urn:snapledger:problem:internal-error"))
                .andExpect(jsonPath("$.detail").value("An unexpected error occurred."))
                .andExpect(jsonPath("$.errorId").isNotEmpty())
                .andReturn().getResponse().getContentAsString();
    }

    private static ServletWebRequest servletRequest(MockHttpServletResponse response) {
        return new ServletWebRequest(new MockHttpServletRequest(), response);
    }

    private static MockHttpServletResponse committedResponse() {
        var response = new MockHttpServletResponse();
        response.setCommitted(true);
        return response;
    }

    record ProbeRequest(@NotBlank @Size(max = 5) String name, @NotNull @Positive Integer quantity) {
    }

    /**
     * Stands in for a feature service validated with @Validated (method validation proxy).
     *
     * <p>PT: Faz o papel de um Service de feature validado com @Validated (proxy de validação de
     * métodos).
     */
    @TestComponent
    @Validated
    static class ProbeService {

        void check(@Size(max = 3) String code) {
            // Reaching here means the code was valid.
            // PT: Chegar aqui significa que o código era válido.
        }

        @Size(max = 3)
        String badResult() {
            return "TOOLONG";
        }
    }

    @TestComponent // never picked up by component scans; registered only by @Import above
    // PT: nunca é pego pelas varreduras de componentes; registrado só pelo @Import acima
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
            // PT: No formato de uma violação de unicidade real do PostgreSQL, vinda pelo Hibernate e
            //     pelo Spring.
            var sql = new SQLException("ERROR: duplicate key value violates unique constraint \"uk_users_email\""
                    + " Detail: Key (lower(email::text))=(" + EMAIL + ") already exists.", "23505");
            var hibernate = new org.hibernate.exception.ConstraintViolationException(
                    "could not execute statement [" + sql.getMessage() + "]", sql, "uk_users_email");
            throw new DataIntegrityViolationException("could not execute statement; " + sql.getMessage(), hibernate);
        }

        @GetMapping(BASE + "/hibernate-duplicate")
        void hibernateDuplicate() {
            // Not translated by Spring (no repository proxy in between), so no DataAccessException.
            // PT: Não traduzida pelo Spring (não há proxy de repositório no meio), então não há
            //     DataAccessException.
            var sql = new SQLException("Detail: Key (lower(email::text))=(" + EMAIL + ") already exists.", "23505");
            throw new org.hibernate.exception.ConstraintViolationException(
                    "could not execute statement [" + sql.getMessage() + "]", sql, "uk_users_email");
        }

        @GetMapping(BASE + "/wrapped-sql")
        void wrappedSql() {
            // RuntimeException(cause) copies cause.toString() into its own message.
            // PT: RuntimeException(cause) copia o cause.toString() para a própria mensagem.
            throw new RuntimeException(new SQLException("Key (email)=(" + EMAIL + ") already exists.", "23505"));
        }

        @GetMapping(BASE + "/suppressed-sql")
        void suppressedSql() {
            // Shaped like a try-with-resources whose close() failed with a driver error.
            // PT: No formato de um try-with-resources cujo close() falhou com um erro do driver.
            var outer = new IllegalStateException("could not finish the import");
            outer.addSuppressed(new SQLException("Key (email)=(" + EMAIL + ") already exists.", "23505"));
            throw outer;
        }

        @GetMapping(BASE + "/jvm-error")
        void jvmError() {
            throw new AssertionError("broken invariant",
                    new DataIntegrityViolationException("Key (email)=(" + EMAIL + ") already exists."));
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

        @GetMapping(BASE + "/too-large")
        void tooLarge() {
            throw new MaxUploadSizeExceededException(1);
        }

        @GetMapping(BASE + "/boom")
        void boom() {
            throw new IllegalStateException(INTERNAL_MESSAGE);
        }

        @GetMapping(BASE + "/client-abort")
        void clientAbort() throws ClientAbortException {
            throw new ClientAbortException(new SocketException("Connection reset"));
        }
    }
}
