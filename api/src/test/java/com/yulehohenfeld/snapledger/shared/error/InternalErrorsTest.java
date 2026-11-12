package com.yulehohenfeld.snapledger.shared.error;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.junit.jupiter.api.Assertions.assertDoesNotThrow;

import java.io.EOFException;
import java.io.IOException;
import java.net.SocketException;
import java.sql.SQLException;
import java.util.UUID;

import ch.qos.logback.classic.Level;
import ch.qos.logback.classic.Logger;

import org.apache.catalina.connector.ClientAbortException;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.postgresql.util.PSQLException;
import org.postgresql.util.PSQLState;
import org.slf4j.LoggerFactory;
import org.springframework.boot.test.system.CapturedOutput;
import org.springframework.boot.test.system.OutputCaptureExtension;
import org.springframework.dao.DataAccessResourceFailureException;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.web.context.request.async.AsyncRequestNotUsableException;

/**
 * The 500 body and its log line, and the exception traversal that decides masking: causes and
 * suppressed exceptions, cycles and very deep chains.
 *
 * <p>PT: O corpo 500 e a sua linha de log, e a travessia de exceções que decide o mascaramento:
 * causas e exceções suprimidas, ciclos e cadeias muito profundas.
 */
@ExtendWith(OutputCaptureExtension.class)
class InternalErrorsTest {

    static final String EMAIL = "bob.secret@example.com";

    @Test
    void bodyIsTheGenericInternalErrorWithAnErrorIdThatIsLogged(CapturedOutput output) {
        var problem = InternalErrors.problem(new IllegalStateException("internal detail"), "/api/v1/x");

        assertThat(problem.getStatus()).isEqualTo(500);
        assertThat(problem.getType()).hasToString("urn:snapledger:problem:internal-error");
        assertThat(problem.getDetail()).isEqualTo("An unexpected error occurred.");
        var errorId = (String) problem.getProperties().get("errorId");
        assertThat(UUID.fromString(errorId)).isNotNull();
        assertThat(output.getAll()).contains(errorId).contains("internal detail");
    }

    @Test
    void missingExceptionIsLoggedWithItsErrorId(CapturedOutput output) {
        var problem = InternalErrors.problem(null, "/api/v1/x");

        assertThat(output.getAll()).contains((String) problem.getProperties().get("errorId"))
                .contains("exception=none");
    }

    @Test
    void failureAfterCommitIsLoggedWithAnErrorIdAndMarkedAsCommitted(CapturedOutput output) {
        InternalErrors.logCommitted(new IllegalStateException("internal detail"));

        assertThat(output.getAll())
                .containsPattern("Unexpected error errorId=[0-9a-f-]{36} responseCommitted=true")
                .contains("internal detail");
    }

    @Test
    void databaseFailureAfterCommitIsLoggedMasked(CapturedOutput output) {
        InternalErrors.logCommitted(new IllegalStateException("outer failure", hibernateViolation()));

        assertThat(output.getAll())
                .containsPattern("Unexpected data access error errorId=[0-9a-f-]{36} "
                        + "exception=java.lang.IllegalStateException constraint=uq_users_email responseCommitted=true")
                .doesNotContain(EMAIL)
                .doesNotContain("outer failure");
    }

    @Test
    void missingFailureAfterCommitIsStillLogged(CapturedOutput output) {
        assertDoesNotThrow(() -> InternalErrors.logCommitted(null));

        assertThat(output.getAll()).contains("exception=none responseCommitted=true");
    }

    @Test
    void databaseErrorAttachedAsSuppressedIsLoggedMasked(CapturedOutput output) {
        // e.g. a try-with-resources whose close() failed with a driver error.
        // PT: por exemplo, um try-with-resources cujo close() falhou com um erro do driver.
        var outer = new IllegalStateException("outer failure");
        outer.addSuppressed(duplicateEmail());

        var problem = InternalErrors.problem(outer, "/api/v1/x");

        assertMaskedLog(output, problem.getProperties().get("errorId"), IllegalStateException.class);
        assertThat(problem.toString()).doesNotContain(EMAIL);
    }

    @Test
    void databaseErrorInTheCauseOfASuppressedExceptionIsFound() {
        var suppressed = new RuntimeException("close failed", duplicateEmail());
        var outer = new IllegalStateException("outer failure");
        outer.addSuppressed(suppressed);

        assertThat(InternalErrors.find(outer, InternalErrors::isDatabaseError)).isInstanceOf(SQLException.class);
    }

    @Test
    void constraintNameIsFoundInsideASuppressedException() {
        var outer = new IllegalStateException("outer failure");
        outer.addSuppressed(new DataIntegrityViolationException("dup", hibernateViolation()));

        assertThat(InternalErrors.constraintName(outer)).isEqualTo("uq_users_email");
    }

    @Test
    void causeCycleTerminates(CapturedOutput output) {
        var a = new RuntimeException("a");
        var b = new RuntimeException("b", a);
        a.initCause(b); // A -> B -> A
        // PT: A -> B -> A (ciclo)

        assertThat(InternalErrors.find(a, InternalErrors::isDatabaseError)).isNull();
        var problem = InternalErrors.problem(a, "/x");
        assertThat(output.getAll()).contains((String) problem.getProperties().get("errorId"));
    }

    @Test
    void causeCycleWithADatabaseErrorIsStillMasked(CapturedOutput output) {
        var a = new RuntimeException("a");
        var b = new RuntimeException("b", a);
        a.initCause(b);
        b.addSuppressed(duplicateEmail());

        var problem = InternalErrors.problem(a, "/x");

        assertMaskedLog(output, problem.getProperties().get("errorId"), RuntimeException.class);
    }

    @Test
    void selfCauseTerminates(CapturedOutput output) {
        // Throwable.initCause refuses "this", so only an override can report itself as the cause.
        // PT: O Throwable.initCause recusa "this", então só uma sobrescrita consegue se apresentar
        //     como a própria causa.
        var self = new RuntimeException("self") {
            @Override
            public synchronized Throwable getCause() {
                return this;
            }
        };

        assertThat(InternalErrors.find(self, InternalErrors::isDatabaseError)).isNull();
        var problem = InternalErrors.problem(self, "/x");
        assertThat(output.getAll()).contains((String) problem.getProperties().get("errorId"));
    }

    @Test
    void suppressedCycleTerminates(CapturedOutput output) {
        var a = new RuntimeException("a");
        var b = new RuntimeException("b");
        a.addSuppressed(b);
        b.addSuppressed(a);

        assertThat(InternalErrors.find(a, InternalErrors::isDatabaseError)).isNull();
        var problem = InternalErrors.problem(a, "/x");
        assertThat(output.getAll()).contains((String) problem.getProperties().get("errorId"));
    }

    @Test
    void veryDeepChainDoesNotOverflowTheStackAndIsMasked(CapturedOutput output) {
        Throwable chain = duplicateEmail();
        for (int i = 0; i < 10_000; i++) {
            // Explicit message: RuntimeException(cause) would copy the growing toString() each level.
            // PT: Mensagem explícita: RuntimeException(cause) copiaria o toString() crescente em
            //     cada nível.
            chain = new RuntimeException("level " + i, chain);
        }

        var problem = InternalErrors.problem(chain, "/x");

        assertMaskedLog(output, problem.getProperties().get("errorId"), RuntimeException.class);
    }

    @Test
    void veryDeepChainWithoutADatabaseErrorDoesNotThrowAndIsLogged(CapturedOutput output) {
        Throwable chain = new IllegalStateException("root");
        for (int i = 0; i < 10_000; i++) {
            chain = new RuntimeException("level " + i, chain);
        }
        var deep = chain;

        var problem = assertDoesNotThrow(() -> InternalErrors.problem(deep, "/x"));

        // Past MAX_NODES the graph is not inspected, so it is masked like a database error.
        // PT: Depois de MAX_NODES o grafo não é inspecionado, então é mascarado como erro de banco.
        assertMaskedLog(output, problem.getProperties().get("errorId"), RuntimeException.class);
    }

    @Test
    void chainJustBelowTheLimitIsStillInspected() {
        Throwable chain = duplicateEmail();
        for (int i = 1; i < InternalErrors.MAX_NODES; i++) {
            chain = new RuntimeException("level " + i, chain);
        }

        assertThat(InternalErrors.find(chain, InternalErrors::isDatabaseError)).isInstanceOf(SQLException.class);
    }

    @Test
    void throwableThatInventsANewCauseOnEveryCallTerminatesAndIsMasked(CapturedOutput output) {
        var endless = new EndlessCause();

        assertThatThrownBy(() -> InternalErrors.find(endless, InternalErrors::isDatabaseError))
                .isInstanceOf(InternalErrors.TraversalLimitExceeded.class);
        var problem = assertDoesNotThrow(() -> InternalErrors.problem(endless, "/x"));
        assertMaskedLog(output, problem.getProperties().get("errorId"), EndlessCause.class);
    }

    @Test
    void throwableThatBreaksTheLoggerFallsBackToTheOneLineMessage(CapturedOutput output) {
        // Not a database error, so the full stack trace is attempted; the logger calls
        // getStackTrace(), which fails here.
        // PT: Não é erro de banco, então o stack trace completo é tentado; o logger chama o
        //     getStackTrace(), que falha aqui.
        var broken = new IllegalStateException("broken " + EMAIL) {
            @Override
            public StackTraceElement[] getStackTrace() {
                throw new IllegalStateException("getStackTrace exploded");
            }
        };

        var problem = assertDoesNotThrow(() -> InternalErrors.problem(broken, "/x"));

        assertThat(output.getAll()).contains("errorId=" + problem.getProperties().get("errorId"))
                .doesNotContain(EMAIL);
    }

    @Test
    void throwableThatFailsWhileBeingInspectedIsMaskedAndDoesNotThrow(CapturedOutput output) {
        var broken = new RuntimeException("broken " + EMAIL) {
            @Override
            public synchronized Throwable getCause() {
                throw new IllegalStateException("getCause exploded");
            }
        };

        var problem = InternalErrors.problem(broken, "/x");

        assertThat(problem.getStatus()).isEqualTo(500);
        assertThat(output.getAll()).contains((String) problem.getProperties().get("errorId"))
                .contains("Unexpected data access error")
                .doesNotContain(EMAIL);
    }

    @Test
    void clientAbortAlongTheCauseChainIsAClientDisconnect() {
        var abort = new ClientAbortException(new SocketException("Connection reset"));

        assertThat(InternalErrors.isClientDisconnect(abort)).isTrue();
        assertThat(InternalErrors.isClientDisconnect(new RuntimeException("wrapped", abort))).isTrue();
        assertThat(InternalErrors.isClientDisconnect(
                new RuntimeException("outer", new RuntimeException("middle", abort)))).isTrue();
        assertThat(InternalErrors.isClientDisconnect(new AsyncRequestNotUsableException("gone"))).isTrue();
    }

    @Test
    void realFailureWithASuppressedClientAbortStaysAnError(CapturedOutput output) {
        // e.g. a close() that failed because the client was gone, attached to the real failure.
        // PT: por exemplo, um close() que falhou porque o cliente já tinha ido embora, anexado à
        //     falha real.
        var failure = new IllegalStateException("real failure");
        failure.addSuppressed(new ClientAbortException(new SocketException("Connection reset")));

        assertThat(InternalErrors.isClientDisconnect(failure)).isFalse();
        withInternalErrorsLevel(Level.DEBUG, () -> InternalErrors.logCommitted(failure));

        assertThat(output.getAll())
                .containsPattern("ERROR .*Unexpected error errorId=[0-9a-f-]{36} responseCommitted=true")
                .contains("real failure")
                .doesNotContain("Client disconnected");
    }

    @Test
    void databaseFailureWithASuppressedClientAbortStaysMasked(CapturedOutput output) {
        var failure = new DataIntegrityViolationException("dup", hibernateViolation());
        failure.addSuppressed(new ClientAbortException(new SocketException("Connection reset")));

        var problem = InternalErrors.problem(failure, "/x");

        assertThat(InternalErrors.isClientDisconnect(failure)).isFalse();
        assertMaskedLog(output, problem.getProperties().get("errorId"), DataIntegrityViolationException.class);
        assertThat(output.getAll()).doesNotContain("Client disconnected");
    }

    @Test
    void causeChainSearchTerminatesOnCyclesAndEndlessChains() {
        var a = new RuntimeException("a");
        var b = new RuntimeException("b", a);
        a.initCause(b);

        assertThat(InternalErrors.isClientDisconnect(a)).isFalse();
        assertThatThrownBy(() -> InternalErrors.findInCauseChain(new EndlessCause(), t -> false))
                .isInstanceOf(InternalErrors.TraversalLimitExceeded.class);
    }

    @Test
    void ioFailuresThatAreNotTheClientsDoingAreNotDisconnects() {
        // Same words as a disconnect, but not the type: the message is never what decides.
        // PT: As mesmas palavras de uma desconexão, mas não o tipo: a mensagem nunca é o que decide.
        assertThat(InternalErrors.isClientDisconnect(new SocketException("Connection reset"))).isFalse();
        assertThat(InternalErrors.isClientDisconnect(new IOException("Broken pipe"))).isFalse();
        assertThat(InternalErrors.isClientDisconnect(new EOFException())).isFalse();
        assertThat(InternalErrors.isClientDisconnect(null)).isFalse();
    }

    @Test
    void databaseConnectionResetStaysAMaskedErrorNotADisconnect(CapturedOutput output) {
        var driver = new PSQLException("An I/O error occurred while sending to the backend.",
                PSQLState.CONNECTION_FAILURE, new SocketException("Connection reset"));
        var failure = new DataAccessResourceFailureException("could not execute statement", driver);

        assertThat(InternalErrors.isClientDisconnect(failure)).isFalse();
        InternalErrors.logCommitted(failure);

        assertThat(output.getAll())
                .contains("Unexpected data access error errorId=")
                .contains("exception=" + DataAccessResourceFailureException.class.getName())
                .doesNotContain("Client disconnected")
                .doesNotContain("\tat ");
    }

    @Test
    void databaseErrorNextToAClientAbortWins() {
        var failure = new RuntimeException("both", new ClientAbortException(new SocketException("reset")));
        failure.addSuppressed(duplicateEmail());

        assertThat(InternalErrors.isClientDisconnect(failure)).isFalse();
    }

    @Test
    void graphThatCannotBeInspectedIsNotADisconnect() {
        assertThat(assertDoesNotThrow(() -> InternalErrors.isClientDisconnect(new EndlessCause()))).isFalse();
    }

    @Test
    void clientDisconnectIsOneDebugLineWithoutMessageOrStackTrace(CapturedOutput output) {
        var abort = new ClientAbortException(EMAIL);

        withInternalErrorsLevel(Level.DEBUG, () -> {
            InternalErrors.logClientDisconnect(abort);
            InternalErrors.logCommitted(abort);
        });

        assertThat(output.getAll())
                .containsPattern("DEBUG .*Client disconnected errorId=[0-9a-f-]{36} "
                        + "exception=org\\.apache\\.catalina\\.connector\\.ClientAbortException\\R")
                .containsPattern("DEBUG .*Client disconnected errorId=[0-9a-f-]{36} "
                        + "exception=org\\.apache\\.catalina\\.connector\\.ClientAbortException responseCommitted=true")
                .doesNotContain("ERROR")
                .doesNotContain(EMAIL)
                .doesNotContain("\tat ");
    }

    @Test
    void clientDisconnectIsSilentAtTheDefaultLevel(CapturedOutput output) {
        withInternalErrorsLevel(Level.INFO,
                () -> InternalErrors.logCommitted(new ClientAbortException(new SocketException("reset"))));

        assertThat(output.getAll()).doesNotContain("errorId=");
    }

    /**
     * Sets the level directly on logback: this class runs without Spring, so its level would
     * otherwise depend on whether an earlier test in the same JVM configured logging.
     *
     * <p>PT: Define o nível direto no logback: esta classe roda sem Spring, então o nível
     * dependeria, caso contrário, de algum teste anterior na mesma JVM ter configurado o log.
     */
    private static void withInternalErrorsLevel(Level level, Runnable action) {
        var logger = (Logger) LoggerFactory.getLogger(InternalErrors.class);
        var previous = logger.getLevel();
        logger.setLevel(level);
        try {
            action.run();
        } finally {
            logger.setLevel(previous);
        }
    }

    private static void assertMaskedLog(CapturedOutput output, Object errorId, Class<?> outer) {
        assertThat(output.getAll())
                .contains("Unexpected data access error errorId=" + errorId)
                .contains("exception=" + outer.getName())
                .doesNotContain(EMAIL)
                .doesNotContain("\tat ");
    }

    private static SQLException duplicateEmail() {
        return new SQLException("Key (lower(email::text))=(" + EMAIL + ") already exists.", "23505");
    }

    private static org.hibernate.exception.ConstraintViolationException hibernateViolation() {
        return new org.hibernate.exception.ConstraintViolationException(
                "could not execute statement", duplicateEmail(), "uq_users_email");
    }

    /**
     * Every getCause() call returns a brand-new object, so an identity set never sees a repeat.
     * No stack trace, so building thousands of them stays cheap.
     *
     * <p>PT: Toda chamada de getCause() devolve um objeto novo, então um conjunto por identidade nunca
     * vê uma repetição. Sem stack trace, então criar milhares delas continua barato.
     */
    static final class EndlessCause extends RuntimeException {

        EndlessCause() {
            super("endless", null, false, false);
        }

        @Override
        public synchronized Throwable getCause() {
            return new EndlessCause();
        }
    }
}
