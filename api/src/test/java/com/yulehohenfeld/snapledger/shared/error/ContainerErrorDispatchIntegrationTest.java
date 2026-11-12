package com.yulehohenfeld.snapledger.shared.error;

import static org.assertj.core.api.Assertions.assertThat;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.net.Socket;
import java.net.SocketException;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.time.Clock;
import java.time.Duration;
import java.util.Arrays;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.stream.Stream;

import jakarta.servlet.Filter;
import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.ServletRequest;
import jakarta.servlet.ServletRequestEvent;
import jakarta.servlet.ServletRequestListener;
import jakarta.servlet.ServletResponse;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;

import ch.qos.logback.classic.Level;

import com.jayway.jsonpath.JsonPath;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.Arguments;
import org.junit.jupiter.params.provider.MethodSource;
import org.junit.jupiter.params.provider.ValueSource;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.logging.LogLevel;
import org.springframework.boot.logging.LoggingSystem;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.context.TestComponent;
import org.springframework.boot.test.system.CapturedOutput;
import org.springframework.boot.test.system.OutputCaptureExtension;
import org.springframework.boot.test.web.server.LocalServerPort;
import org.springframework.boot.tomcat.TomcatWebServer;
import org.springframework.boot.web.server.servlet.context.ServletWebServerApplicationContext;
import org.springframework.boot.webmvc.autoconfigure.DispatcherServletRegistrationBean;
import org.springframework.context.annotation.Import;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.http.converter.HttpMessageNotWritableException;
import org.springframework.test.util.ReflectionTestUtils;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RestController;

import com.yulehohenfeld.snapledger.support.TestJwtSecret;
import com.yulehohenfeld.snapledger.support.TestTokens;
import com.yulehohenfeld.snapledger.support.TestcontainersConfiguration;

/**
 * Errors the servlet container forwards to /error (ADR 0007), against a real Tomcat. Only what
 * MockMvc cannot prove lives here: a real ERROR dispatch through the security chain, the
 * firewall, the forward itself and Tomcat's own logging. The body rules of /error are covered by
 * ProblemErrorControllerTest. Two real sources are used: the security firewall rejecting a path
 * with {@code ;}, and a servlet filter whose exception escapes Spring MVC entirely, before or after
 * the response is committed (the second case is logged by CommittedResponseFailureFilter). A probe
 * controller covers what only a real connection shows inside MVC: a failure after commit and a
 * client that resets the connection.
 *
 * <p>This context differs from the other Spring Boot tests (random port plus the probe filter),
 * so Spring cannot reuse their cached context and this class starts its own PostgreSQL
 * container. Accepted: aligning the contexts is out of scope for now.
 *
 * <p>PT: Erros que o servlet container encaminha para /error (ADR 0007), contra um Tomcat de
 * verdade. Só o que o MockMvc não consegue provar fica aqui: um dispatch ERROR real pela cadeia de
 * segurança, o firewall, o próprio encaminhamento e o log do próprio Tomcat. As regras de corpo do
 * /error são cobertas pelo ProblemErrorControllerTest. Duas fontes reais são usadas: o firewall de
 * segurança recusando um caminho com {@code ;}, e um filtro de servlet cuja exceção escapa
 * totalmente do Spring MVC, antes ou depois de a resposta ser enviada (o segundo caso é registrado
 * pelo CommittedResponseFailureFilter). Um controller de teste cobre o que só uma conexão real
 * mostra dentro do MVC: uma falha depois do envio e um cliente que reseta a conexão. Este contexto
 * é diferente dos outros testes Spring Boot (porta
 * aleatória mais o filtro de teste), então o Spring não consegue reaproveitar o contexto em cache
 * deles e esta classe sobe o próprio container PostgreSQL. Aceito: alinhar os contextos está fora
 * do escopo por enquanto.
 */
@ExtendWith(OutputCaptureExtension.class)
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
@Import({TestcontainersConfiguration.class, TestJwtSecret.class, ContainerErrorDispatchIntegrationTest.EscapingFilter.class,
        ContainerErrorDispatchIntegrationTest.StreamingProbe.class, ContainerErrorDispatchIntegrationTest.FinishedRequests.class})
class ContainerErrorDispatchIntegrationTest {

    static final String PROBE = "/api/v1/probe";
    static final String PUBLIC_PROBE = "/docs/probe";
    static final String ESCAPE = PROBE + "/escape";
    static final String ESCAPE_DATABASE = PROBE + "/escape-database";
    static final String INTERNAL_MESSAGE = "probe internal detail on host db-internal";
    static final String EMAIL = "dave.secret@example.com";

    // One client for the whole class. Pinned to HTTP/1.1: by default the JDK client adds an h2c
    // upgrade request to every plain-HTTP call, an extra variable these tests do not need.
    // PT: Um cliente para a classe inteira. Fixado em HTTP/1.1: por padrão o cliente do JDK
    //     adiciona um pedido de upgrade h2c a toda chamada HTTP simples, uma variável extra de que
    //     estes testes não precisam.
    private static final HttpClient HTTP = HttpClient.newBuilder()
            .version(HttpClient.Version.HTTP_1_1)
            .connectTimeout(Duration.ofSeconds(5))
            .build();

    @LocalServerPort
    int port;

    @Autowired
    Clock clock;

    @Autowired
    ServletWebServerApplicationContext webServerContext;

    @Autowired
    DispatcherServletRegistrationBean dispatcherServlet;

    static Stream<Arguments> firewallRejections() {
        return Stream.of(
                Arguments.of("anonymous", "GET", "/api/v1/expenses;x=1", Map.of()),
                Arguments.of("under the auth path", "POST", "/api/v1/auth/login;x",
                        Map.of(HttpHeaders.CONTENT_TYPE, MediaType.APPLICATION_JSON_VALUE)),
                Arguments.of("garbage Authorization header", "GET", "/api/v1/expenses;x=1",
                        Map.of(HttpHeaders.AUTHORIZATION, "Bearer not-a-jwt")),
                Arguments.of("HTML Accept header", "GET", "/api/v1/expenses;x=1",
                        Map.of(HttpHeaders.ACCEPT, MediaType.TEXT_HTML_VALUE)));
    }

    @ParameterizedTest(name = "{0}")
    @MethodSource("firewallRejections")
    void firewallRejectionIsBadRequestProblem(String caseName, String method, String path,
                                             Map<String, String> headers) throws Exception {
        var response = send(method, path, headers);

        expectProblem(response, 400, "urn:snapledger:problem:validation-error");
        assertThat(JsonPath.<String>read(response.body(), "$.instance")).isEqualTo(path);
        // The firewall answers before Spring Security's header filter, so these come from
        // ProblemErrorController alone.
        // PT: O firewall responde antes do filtro de headers do Spring Security, então estes vêm
        //     só do ProblemErrorController.
        assertThat(response.headers().firstValue(ProblemErrorController.X_CONTENT_TYPE_OPTIONS)).hasValue("nosniff");
        assertThat(response.headers().allValues(HttpHeaders.CACHE_CONTROL)).contains("no-store");
    }

    @Test
    void exceptionEscapingMvcIsInternalErrorWithAnErrorIdAndNoInternals(CapturedOutput output) throws Exception {
        var response = send("GET", ESCAPE, authenticated());

        expectProblem(response, 500, "urn:snapledger:problem:internal-error");
        String errorId = JsonPath.read(response.body(), "$.errorId");
        assertThat(UUID.fromString(errorId)).isNotNull();
        assertThat(JsonPath.<String>read(response.body(), "$.instance")).isEqualTo(ESCAPE);
        assertThat(response.body())
                .doesNotContain(INTERNAL_MESSAGE)
                .doesNotContain("IllegalStateException")
                .doesNotContain("at com.");
        assertThat(output.getAll()).contains("Unexpected error errorId=" + errorId).contains(INTERNAL_MESSAGE);
    }

    @Test
    void databaseCauseOfAnErrorEscapingMvcIsNeverLoggedByAnyLogger(CapturedOutput output) throws Exception {
        var response = send("GET", ESCAPE_DATABASE, authenticated());

        expectProblem(response, 500, "urn:snapledger:problem:internal-error");
        String errorId = JsonPath.read(response.body(), "$.errorId");
        assertThat(response.body()).doesNotContain(EMAIL);
        assertThat(output.getAll())
                .contains("Unexpected data access error errorId=" + errorId)
                .contains("exception=")
                // The whole output, not only the API line: Tomcat's wrapper logger would print the
                // cause chain unmasked if logback-spring.xml did not turn it off.
                // PT: A saída inteira, não só a linha da API: o logger do wrapper do Tomcat
                //     imprimiria a cadeia de causas sem máscara se o logback-spring.xml não o
                //     desligasse.
                .doesNotContain(EMAIL)
                .doesNotContain("already exists");
    }

    // The anonymous case needs a path chain 2 permits, so the request reaches the probe filter;
    // /docs/** is public. Without CommittedResponseFailureFilter neither case logged anything.
    // PT: O caso anônimo precisa de um caminho que a cadeia 2 permite, para a requisição chegar ao
    //     filtro de teste; /docs/** é público. Sem o CommittedResponseFailureFilter nenhum dos dois
    //     casos registrava nada.
    @ParameterizedTest(name = "{0}")
    @ValueSource(strings = {"anonymous", "authenticated"})
    void databaseFailureAfterTheResponseIsCommittedIsLoggedMaskedExactlyOnce(String caller, CapturedOutput output)
            throws Exception {
        var anonymous = "anonymous".equals(caller);
        var path = anonymous ? PUBLIC_PROBE + "/escape-committed" : PROBE + "/escape-committed";

        try {
            send("GET", path, anonymous ? Map.of() : authenticated());
        } catch (IOException expected) {
            // Tomcat closes the connection in the middle of the chunked body: the client cannot
            // read a complete response, which is the container's documented signal for this case.
            // PT: O Tomcat fecha a conexão no meio do corpo chunked: o cliente não consegue ler
            //     uma resposta completa, que é o sinal documentado do container para este caso.
        }

        var all = awaitLogged(output, "responseCommitted=true");
        assertThat(occurrences(all, "errorId=")).isEqualTo(1);
        assertThat(all)
                .contains("Unexpected data access error errorId=")
                .contains("responseCommitted=true")
                .doesNotContain(EMAIL)
                .doesNotContain("already exists");
    }

    @ParameterizedTest(name = "{0}")
    @ValueSource(strings = {"anonymous", "authenticated"})
    void databaseFailureBeforeTheResponseIsCommittedIsLoggedOnceByTheErrorPath(String caller, CapturedOutput output)
            throws Exception {
        var anonymous = "anonymous".equals(caller);
        var path = anonymous ? PUBLIC_PROBE + "/escape-database" : ESCAPE_DATABASE;

        var response = send("GET", path, anonymous ? Map.of() : authenticated());

        expectProblem(response, 500, "urn:snapledger:problem:internal-error");
        String errorId = JsonPath.read(response.body(), "$.errorId");
        var all = output.getAll();
        assertThat(occurrences(all, "errorId=")).isEqualTo(1);
        assertThat(all)
                .contains("Unexpected data access error errorId=" + errorId)
                .doesNotContain("responseCommitted=true")
                .doesNotContain(EMAIL);
    }

    // A controller that has already streamed more than Tomcat's 8 KB buffer and then fails: the
    // exception reaches the catch-all (handleUnexpected) with the response committed. It is
    // rethrown, so the failure leaves MVC, CommittedResponseFailureFilter logs it once and Tomcat
    // aborts the connection: the wire shows the 200 and the streamed bytes, but never the last
    // chunk ("0"), so no client can take the cut body for a whole one.
    // PT: Um controller que já enviou mais do que o buffer de 8 KB do Tomcat e então falha: a
    //     exceção chega ao pega-tudo (handleUnexpected) com a resposta já enviada. Ela é relançada,
    //     então a falha sai do MVC, o CommittedResponseFailureFilter a registra uma vez e o Tomcat
    //     aborta a conexão: o que passa na rede mostra o 200 e os bytes enviados, mas nunca o
    //     último chunk ("0"), então nenhum cliente pode tomar o corpo cortado por completo.
    @Test
    void controllerFailureAfterCommitAbortsTheConnectionAndIsLoggedMaskedExactlyOnce(CapturedOutput output)
            throws Exception {
        var path = PROBE + "/mvc/committed";
        var finished = FinishedRequests.expect(path);

        var wire = rawGet(path, authenticated());

        assertThat(finished.await(5, TimeUnit.SECONDS)).isTrue();
        assertThat(wire)
                .startsWith("HTTP/1.1 200")
                .containsIgnoringCase("Transfer-Encoding: chunked")
                .contains("x".repeat(1024))
                .doesNotContain("\r\n0\r\n\r\n")
                .doesNotContain("errorId");
        assertLoggedMaskedOnceAfterCommit(output.getAll());
    }

    /**
     * A framework 5xx after commit (handleExceptionInternal) is handled, not rethrown: rethrown,
     * DefaultHandlerExceptionResolver resolved it with two unmasked WARNs ("Ignoring exception,
     * response committed already: " + toString), Tomcat still wrote the last chunk and nothing
     * reached the filter, so no errorId line at all. Kept as a guard: the response ends normally
     * (a cut body the client cannot tell from a whole one, ADR 0007 Consequences), but it is logged
     * once, masked, and no resolver prints the exception.
     *
     * <p>PT: Um 5xx do framework depois do envio (handleExceptionInternal) é tratado, não relançado:
     * relançado, o DefaultHandlerExceptionResolver o resolvia com dois WARNs sem máscara ("Ignoring
     * exception, response committed already: " + toString), o Tomcat escrevia o último chunk mesmo
     * assim e nada chegava ao filtro, então não havia linha com errorId nenhuma. Mantido como
     * proteção: a resposta termina normalmente (um corpo cortado que o cliente não distingue de um
     * completo, ADR 0007 Consequências), mas é registrada uma vez, mascarada, e nenhum resolver
     * imprime a exceção.
     */
    @Test
    void frameworkFailureAfterCommitIsHandledAndLoggedMaskedExactlyOnce(CapturedOutput output) throws Exception {
        var path = PROBE + "/mvc/committed-framework";
        var finished = FinishedRequests.expect(path);

        var wire = rawGet(path, authenticated());

        assertThat(finished.await(5, TimeUnit.SECONDS)).isTrue();
        assertThat(wire)
                .startsWith("HTTP/1.1 200")
                .contains("x".repeat(1024))
                .endsWith("\r\n0\r\n\r\n")
                .doesNotContain("errorId");
        var all = output.getAll();
        assertLoggedMaskedOnceAfterCommit(all);
        assertThat(all)
                .doesNotContain("DefaultHandlerExceptionResolver")
                .doesNotContain("Ignoring exception");
    }

    private static void assertLoggedMaskedOnceAfterCommit(String all) {
        assertThat(occurrences(all, "errorId=")).isEqualTo(1);
        assertThat(all)
                .contains("Unexpected data access error errorId=")
                .contains("responseCommitted=true")
                .doesNotContain("Response already committed")
                .doesNotContain("Failure in @ExceptionHandler")
                .doesNotContain(EMAIL)
                .doesNotContain("already exists");
    }

    // Positive control for the check above: a response that ends normally does carry the last
    // chunk, so its absence really means the connection was aborted.
    // PT: Controle positivo da verificação acima: uma resposta que termina normalmente traz o
    //     último chunk, então a ausência dele significa mesmo que a conexão foi abortada.
    @Test
    void streamedResponseThatEndsNormallyCarriesTheLastChunk() throws Exception {
        assertThat(rawGet(PROBE + "/mvc/complete", authenticated()))
                .startsWith("HTTP/1.1 200")
                .containsIgnoringCase("Transfer-Encoding: chunked")
                .endsWith("\r\n0\r\n\r\n");
    }

    /**
     * Sends a GET over a plain socket and returns every byte the server sent until it closed or
     * reset the connection. A real client library would hide exactly what is checked here: whether
     * the chunked body ended with its last chunk or was cut. {@code Connection: close} makes a
     * normal response end with the server's close, so both cases finish without a timeout.
     *
     * <p>PT: Envia um GET por um socket simples e devolve todo byte que o servidor enviou até fechar
     * ou resetar a conexão. Uma biblioteca de cliente de verdade esconderia exatamente o que é
     * conferido aqui: se o corpo chunked terminou com o último chunk ou foi cortado.
     * {@code Connection: close} faz uma resposta normal terminar com o fechamento pelo servidor,
     * então os dois casos acabam sem esperar um timeout.
     */
    private String rawGet(String path, Map<String, String> headers) throws IOException {
        var request = new StringBuilder("GET " + path + " HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n");
        headers.forEach((name, value) -> request.append(name).append(": ").append(value).append("\r\n"));
        request.append("\r\n");
        var received = new ByteArrayOutputStream();
        try (var socket = new Socket("localhost", port)) {
            socket.setSoTimeout(10_000);
            socket.getOutputStream().write(request.toString().getBytes(StandardCharsets.US_ASCII));
            socket.getOutputStream().flush();
            var in = socket.getInputStream();
            var buffer = new byte[8192];
            try {
                for (int read = in.read(buffer); read >= 0; read = in.read(buffer)) {
                    received.write(buffer, 0, read);
                }
            } catch (SocketException reset) {
                // An abort may arrive as a TCP reset instead of a close; the bytes read so far are
                // what the client got.
                // PT: Um aborto pode chegar como um reset TCP em vez de um fechamento; os bytes lidos
                //     até ali são o que o cliente recebeu.
            }
        }
        return received.toString(StandardCharsets.ISO_8859_1);
    }

    /**
     * The reviewer's scenario: a client resets the connection while a controller streams. Spring 7
     * wraps the response's output stream and turns the failed write into
     * AsyncRequestNotUsableException, which ResponseEntityExceptionHandler itself answers (nothing
     * written) with one DEBUG line of its own. Neither our handler nor the filter sees it, so no
     * errorId and no ERROR. Kept as a guard: a Spring upgrade that changes this fails here.
     *
     * <p>PT: O cenário do revisor: um cliente reseta a conexão enquanto um controller está enviando.
     * O Spring 7 envolve o output stream da resposta e transforma a escrita que falhou em
     * AsyncRequestNotUsableException, que o próprio ResponseEntityExceptionHandler trata (sem
     * escrever nada) com uma linha DEBUG dele. Nem o nosso handler nem o filtro a veem, então não há
     * errorId nem ERROR. Mantido como proteção: um upgrade do Spring que mude isso falha aqui.
     */
    @Test
    void clientThatResetsTheConnectionWhileAControllerStreamsLeavesNoErrorLine(CapturedOutput output)
            throws Exception {
        var path = PUBLIC_PROBE + "/mvc/abort";
        var finished = FinishedRequests.expect(path);

        try (var socket = new Socket("localhost", port)) {
            socket.setSoTimeout(5_000);
            socket.getOutputStream().write(("GET " + path + " HTTP/1.1\r\nHost: localhost\r\n\r\n")
                    .getBytes(StandardCharsets.US_ASCII));
            socket.getOutputStream().flush();
            // The first bytes prove the response is committed and streaming.
            // PT: Os primeiros bytes provam que a resposta já foi enviada e está em andamento.
            assertThat(socket.getInputStream().read(new byte[1024])).isPositive();
            resetOnClose(socket);
        }

        assertThat(finished.await(10, TimeUnit.SECONDS)).isTrue();
        assertNoErrorLine(output.getAll());
    }

    /**
     * A client that resets the connection while a controller reads the raw request body: Spring
     * does not wrap the input stream, so Tomcat's ClientAbortException reaches the catch-all. That
     * is the client's doing, not a server failure: one DEBUG line without stack trace or message,
     * no ERROR, nothing written. The logger is raised to DEBUG only for this test, so the line can
     * be counted.
     *
     * <p>PT: Um cliente que reseta a conexão enquanto um controller lê o corpo bruto da requisição:
     * o Spring não envolve o input stream, então o ClientAbortException do Tomcat chega ao
     * pega-tudo. Isso é obra do cliente, não falha do servidor: uma linha DEBUG sem stack trace nem
     * mensagem, nenhum ERROR, nada escrito. O logger sobe para DEBUG só neste teste, para que a
     * linha possa ser contada.
     */
    @Test
    void clientThatResetsTheConnectionDuringTheRequestBodyLeavesOneShortDebugLine(CapturedOutput output)
            throws Exception {
        var path = PUBLIC_PROBE + "/mvc/upload";
        var finished = FinishedRequests.expect(path);
        var reading = StreamingProbe.expectUpload();
        var logging = LoggingSystem.get(getClass().getClassLoader());
        logging.setLogLevel(InternalErrors.class.getName(), LogLevel.DEBUG);
        try {
            try (var socket = new Socket("localhost", port)) {
                socket.getOutputStream().write(("POST " + path + " HTTP/1.1\r\nHost: localhost\r\n"
                        + "Content-Type: application/octet-stream\r\nContent-Length: 1048576\r\n\r\n"
                        + "only the first bytes").getBytes(StandardCharsets.US_ASCII));
                socket.getOutputStream().flush();
                assertThat(reading.await(5, TimeUnit.SECONDS)).isTrue();
                resetOnClose(socket);
            }
            assertThat(finished.await(10, TimeUnit.SECONDS)).isTrue();
        } finally {
            logging.setLogLevel(InternalErrors.class.getName(), null);
        }

        var all = output.getAll();
        assertThat(occurrences(all, "errorId=")).isEqualTo(1);
        // Tomcat 11 already reports the response as committed once the connection has failed, so
        // the line may carry the suffix; either way it is the one short DEBUG line.
        // PT: O Tomcat 11 já informa a resposta como enviada quando a conexão falhou, então a linha
        //     pode levar o sufixo; de qualquer forma é a única linha DEBUG curta.
        assertThat(all).containsPattern("DEBUG .*Client disconnected errorId=[0-9a-f-]{36} "
                + "exception=org\\.apache\\.catalina\\.connector\\.ClientAbortException( responseCommitted=true)?\\R");
        assertNoErrorLine(all);
    }

    // Linger 0: close() sends a TCP reset instead of a normal close, like a client whose app was
    // killed or whose network dropped.
    // PT: Linger 0: o close() envia um reset TCP em vez de um fechamento normal, como um cliente
    //     cujo app foi encerrado ou cuja rede caiu.
    private static void resetOnClose(Socket socket) throws IOException {
        socket.setSoLinger(true, 0);
    }

    private static void assertNoErrorLine(String all) {
        assertThat(all)
                .doesNotContain(" ERROR ")
                .doesNotContain("Unexpected error")
                .doesNotContain("\tat ")
                .doesNotContain("Failure in @ExceptionHandler");
    }

    /**
     * logback-spring.xml hard-codes the name of Tomcat's wrapper logger. Here the name is taken from
     * the running Tomcat itself (the wrapper of the dispatcher servlet, inside its context), so a
     * new context path or servlet name fails this test instead of silently bringing the unmasked
     * copy back.
     *
     * <p>PT: O logback-spring.xml fixa no texto o nome do logger do wrapper do Tomcat. Aqui o nome é
     * tirado do próprio Tomcat em execução (o wrapper do dispatcher servlet, dentro do seu
     * contexto), então um novo context path ou nome de servlet faz este teste falhar em vez de
     * trazer de volta, em silêncio, a cópia sem máscara.
     */
    @Test
    void tomcatWrapperLoggerOfTheDispatcherServletIsOff() {
        var tomcat = ((TomcatWebServer) webServerContext.getWebServer()).getTomcat();
        var wrapper = Arrays.stream(tomcat.getHost().findChildren())
                .flatMap(context -> Arrays.stream(context.findChildren()))
                .filter(child -> child.getName().equals(dispatcherServlet.getServletName()))
                .findFirst()
                .orElseThrow();
        String loggerName = ReflectionTestUtils.invokeMethod(wrapper, "getLogName");

        var logger = (ch.qos.logback.classic.Logger) LoggerFactory.getLogger(loggerName);
        assertThat(logger.getEffectiveLevel()).isEqualTo(Level.OFF);
    }

    /**
     * The server logs before it closes the connection, but the client can see the close first, so
     * the output is polled for a short time instead of read once.
     *
     * <p>PT: O servidor registra o log antes de fechar a conexão, mas o cliente pode ver o
     * fechamento antes, então a saída é consultada por pouco tempo em vez de lida uma vez só.
     */
    private static String awaitLogged(CapturedOutput output, String text) throws InterruptedException {
        var deadline = System.nanoTime() + Duration.ofSeconds(5).toNanos();
        while (!output.getAll().contains(text) && System.nanoTime() < deadline) {
            Thread.sleep(50);
        }
        return output.getAll();
    }

    private static int occurrences(String text, String part) {
        int count = 0;
        for (int at = text.indexOf(part); at >= 0; at = text.indexOf(part, at + part.length())) {
            count++;
        }
        return count;
    }

    private HttpResponse<String> send(String method, String path, Map<String, String> headers)
            throws IOException, InterruptedException {
        var builder = HttpRequest.newBuilder(URI.create("http://localhost:" + port + path))
                .timeout(Duration.ofSeconds(10))
                .method(method, "POST".equals(method)
                        ? HttpRequest.BodyPublishers.ofString("{}")
                        : HttpRequest.BodyPublishers.noBody());
        headers.forEach(builder::header);
        return HTTP.send(builder.build(), HttpResponse.BodyHandlers.ofString());
    }

    private static void expectProblem(HttpResponse<String> response, int status, String type) {
        assertThat(response.statusCode()).isEqualTo(status);
        assertThat(response.headers().firstValue(HttpHeaders.CONTENT_TYPE)).hasValueSatisfying(
                value -> assertThat(MediaType.parseMediaType(value).isCompatibleWith(MediaType.APPLICATION_PROBLEM_JSON)).isTrue());
        assertThat(response.headers().firstValue(HttpHeaders.WWW_AUTHENTICATE)).isEmpty();
        assertThat(JsonPath.<String>read(response.body(), "$.type")).isEqualTo(type);
        assertThat(JsonPath.<Integer>read(response.body(), "$.status")).isEqualTo(status);
    }

    /**
     * A valid access token signed with the application's key and clock.
     *
     * <p>PT: Um token de acesso válido, assinado com a chave e o relógio da aplicação.
     */
    private Map<String, String> authenticated() {
        return Map.of(HttpHeaders.AUTHORIZATION, TestTokens.bearer(TestTokens.valid(clock.instant())));
    }

    /**
     * Throws after the security filters and before Spring MVC, so neither GlobalExceptionHandler
     * nor any resolver sees the failure and Tomcat forwards it to /error. A plain Filter bean is
     * registered by Boot for REQUEST dispatches only, so it does not run again on /error.
     *
     * <p>PT: Lança exceção depois dos filtros de segurança e antes do Spring MVC, então nem o
     * GlobalExceptionHandler nem nenhum resolver vê a falha e o Tomcat a encaminha para /error. Um
     * Filter simples é registrado pelo Boot só para dispatches REQUEST, então não roda de novo no
     * /error.
     */
    @TestComponent
    static class EscapingFilter implements Filter {

        @Override
        public void doFilter(ServletRequest request, ServletResponse response, FilterChain chain)
                throws IOException, ServletException {
            var path = ((HttpServletRequest) request).getRequestURI();
            if (!path.startsWith(PROBE + "/") && !path.startsWith(PUBLIC_PROBE + "/")) {
                chain.doFilter(request, response);
                return;
            }
            if (path.endsWith("/escape")) {
                throw new IllegalStateException(INTERNAL_MESSAGE);
            }
            if (path.endsWith("/escape-database")) {
                throw new AssertionError("broken invariant",
                        new DataIntegrityViolationException("Key (email)=(" + EMAIL + ") already exists."));
            }
            if (path.endsWith("/escape-committed")) {
                // Output stream, like Spring MVC's message converters: the body has started, so
                // the container can no longer forward to /error.
                // PT: Output stream, como os conversores de mensagem do Spring MVC: o corpo já
                //     começou, então o container não consegue mais fazer forward para /error.
                response.getOutputStream().write("partial".getBytes(StandardCharsets.UTF_8));
                response.flushBuffer();
                throw new AssertionError("broken invariant after commit",
                        new DataIntegrityViolationException("Key (email)=(" + EMAIL + ") already exists."));
            }
            chain.doFilter(request, response);
        }
    }

    /**
     * Spring MVC endpoints that fail after the response is committed, plus one that streams and
     * ends normally (the control). Only registered by this test's {@code @Import}.
     *
     * <p>PT: Endpoints do Spring MVC que falham depois que a resposta foi enviada, mais um que envia
     * e termina normalmente (o controle). Registrados só pelo {@code @Import} deste teste.
     */
    @TestComponent
    @RestController
    static class StreamingProbe {

        // Twice Tomcat's default 8 KB buffer: one chunk, flushed, commits the response.
        // PT: O dobro do buffer padrão de 8 KB do Tomcat: um pedaço, com flush, envia (commit) a
        //     resposta.
        static final int CHUNK_BYTES = 16 * 1024;

        private static volatile CountDownLatch uploadReading = new CountDownLatch(1);

        static CountDownLatch expectUpload() {
            uploadReading = new CountDownLatch(1);
            return uploadReading;
        }

        @GetMapping(PROBE + "/mvc/committed")
        void committed(HttpServletResponse response) throws IOException {
            writeChunk(response);
            throw new IllegalStateException("broken invariant after commit", duplicateEmail());
        }

        @GetMapping(PROBE + "/mvc/committed-framework")
        void committedFramework(HttpServletResponse response) throws IOException {
            writeChunk(response);
            throw new HttpMessageNotWritableException("could not write", duplicateEmail());
        }

        @GetMapping(PROBE + "/mvc/complete")
        void complete(HttpServletResponse response) throws IOException {
            writeChunk(response);
        }

        /**
         * Streams slowly until the client goes away; the write after the reset throws. Bounded, so
         * a client that never resets fails the test instead of hanging it.
         *
         * <p>PT: Envia devagar até o cliente sumir; a escrita depois do reset lança exceção.
         * Limitado, então um cliente que nunca reseta faz o teste falhar em vez de travá-lo.
         */
        @GetMapping(PUBLIC_PROBE + "/mvc/abort")
        void abort(HttpServletResponse response) throws IOException, InterruptedException {
            for (int i = 0; i < 1_000; i++) {
                writeChunk(response);
                Thread.sleep(10);
            }
        }

        /**
         * Reads the raw body, like a future upload endpoint would; the test resets the connection
         * once the read has started.
         *
         * <p>PT: Lê o corpo bruto, como um futuro endpoint de upload faria; o teste reseta a conexão
         * assim que a leitura começou.
         */
        @PostMapping(PUBLIC_PROBE + "/mvc/upload")
        void upload(HttpServletRequest request) throws IOException {
            var body = request.getInputStream();
            body.read();
            uploadReading.countDown();
            body.readAllBytes();
        }

        private static void writeChunk(HttpServletResponse response) throws IOException {
            var chunk = new byte[CHUNK_BYTES];
            Arrays.fill(chunk, (byte) 'x');
            response.getOutputStream().write(chunk);
            response.flushBuffer();
        }

        private static DataIntegrityViolationException duplicateEmail() {
            return new DataIntegrityViolationException("Key (email)=(" + EMAIL + ") already exists.");
        }
    }

    /**
     * Tells a test when Tomcat has completely finished a request, including the error handling
     * and every filter's logging, so "logged exactly once" is checked after the last line could
     * have been written instead of after a guessed sleep.
     *
     * <p>PT: Avisa o teste quando o Tomcat terminou completamente uma requisição, incluindo o
     * tratamento de erro e o log de todos os filtros, para que "registrado exatamente uma vez" seja
     * conferido depois que a última linha poderia ter sido escrita, e não depois de uma espera
     * chutada.
     */
    @TestComponent
    static class FinishedRequests implements ServletRequestListener {

        private static final Map<String, CountDownLatch> WAITING = new ConcurrentHashMap<>();

        static CountDownLatch expect(String path) {
            var latch = new CountDownLatch(1);
            WAITING.put(path, latch);
            return latch;
        }

        @Override
        public void requestDestroyed(ServletRequestEvent event) {
            if (event.getServletRequest() instanceof HttpServletRequest http) {
                var latch = WAITING.remove(http.getRequestURI());
                if (latch != null) {
                    latch.countDown();
                }
            }
        }
    }
}
