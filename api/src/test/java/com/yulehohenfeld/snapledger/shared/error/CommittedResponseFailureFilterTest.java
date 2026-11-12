package com.yulehohenfeld.snapledger.shared.error;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.catchThrowable;

import java.io.IOException;
import java.net.SocketException;

import org.apache.catalina.connector.ClientAbortException;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.springframework.boot.test.system.CapturedOutput;
import org.springframework.boot.test.system.OutputCaptureExtension;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.mock.web.MockHttpServletResponse;

/**
 * The filter's own rule, without a server: log only when the response is committed, and always
 * rethrow the same failure. The real Tomcat behavior is in ContainerErrorDispatchIntegrationTest.
 *
 * <p>PT: A regra do próprio filtro, sem servidor: registrar só quando a resposta já foi enviada, e
 * sempre relançar a mesma falha. O comportamento com um Tomcat real está no
 * ContainerErrorDispatchIntegrationTest.
 */
@ExtendWith(OutputCaptureExtension.class)
class CommittedResponseFailureFilterTest {

    private final CommittedResponseFailureFilter filter = new CommittedResponseFailureFilter();

    @Test
    void failureAfterCommitIsLoggedAndRethrownUnchanged(CapturedOutput output) {
        var response = new MockHttpServletResponse();
        var failure = new IOException("write failed");

        var thrown = catchThrowable(() -> filter.doFilter(new MockHttpServletRequest(), response, (req, res) -> {
            response.setCommitted(true);
            throw failure;
        }));

        assertThat(thrown).isSameAs(failure);
        assertThat(output.getAll()).contains("responseCommitted=true").contains("write failed");
    }

    // A client reset after commit (e.g. a filter flushing to a closed connection) is not a server
    // failure: no ERROR and no stack trace, whatever level the logger runs at in this JVM.
    // PT: Um reset do cliente depois do envio (por exemplo um filtro fazendo flush numa conexão
    //     fechada) não é falha do servidor: nenhum ERROR e nenhum stack trace, seja qual for o
    //     nível do logger nesta JVM.
    @Test
    void clientDisconnectAfterCommitIsRethrownWithoutAnErrorLine(CapturedOutput output) {
        var response = new MockHttpServletResponse();
        var failure = new ClientAbortException(new SocketException("Connection reset"));

        var thrown = catchThrowable(() -> filter.doFilter(new MockHttpServletRequest(), response, (req, res) -> {
            response.setCommitted(true);
            throw failure;
        }));

        assertThat(thrown).isSameAs(failure);
        assertThat(output.getAll()).doesNotContain("ERROR").doesNotContain("\tat ");
    }

    @Test
    void failureBeforeCommitIsOnlyRethrownBecauseTheErrorPathLogsIt(CapturedOutput output) {
        var failure = new IllegalStateException("not yet committed");

        var thrown = catchThrowable(() -> filter.doFilter(new MockHttpServletRequest(), new MockHttpServletResponse(),
                (req, res) -> {
                    throw failure;
                }));

        assertThat(thrown).isSameAs(failure);
        assertThat(output.getAll()).doesNotContain("errorId=");
    }

    @Test
    void errorsAreRethrownToo(CapturedOutput output) {
        var response = new MockHttpServletResponse();
        response.setCommitted(true);
        var failure = new AssertionError("broken invariant");

        var thrown = catchThrowable(() -> filter.doFilter(new MockHttpServletRequest(), response, (req, res) -> {
            throw failure;
        }));

        assertThat(thrown).isSameAs(failure);
        assertThat(output.getAll()).contains("responseCommitted=true");
    }

    @Test
    void successfulRequestIsNotTouched(CapturedOutput output) throws Exception {
        var response = new MockHttpServletResponse();

        filter.doFilter(new MockHttpServletRequest(), response, (req, res) -> res.getWriter().write("ok"));

        assertThat(response.getContentAsString()).isEqualTo("ok");
        assertThat(output.getAll()).doesNotContain("errorId=");
    }
}
