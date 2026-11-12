package com.yulehohenfeld.snapledger.shared.error;

import java.sql.SQLException;
import java.util.ArrayDeque;
import java.util.Collections;
import java.util.IdentityHashMap;
import java.util.Set;
import java.util.UUID;
import java.util.function.Predicate;

import jakarta.persistence.PersistenceException;

import lombok.extern.slf4j.Slf4j;

import org.apache.catalina.connector.ClientAbortException;
import org.hibernate.JDBCException;
import org.springframework.dao.DataAccessException;
import org.springframework.http.HttpStatus;
import org.springframework.http.ProblemDetail;
import org.springframework.web.context.request.async.AsyncRequestNotUsableException;

/**
 * The one place that turns an unexpected failure into the {@code 500 internal-error} body and
 * its log line. Shared by GlobalExceptionHandler (errors inside MVC) and ProblemErrorController
 * (errors the servlet container forwards to /error, ADR 0007), so both mask database errors the
 * same way. CommittedResponseFailureFilter uses the same log line for failures after commit.
 *
 * <p>PT: O único lugar que transforma uma falha inesperada no corpo {@code 500 internal-error} e na
 * sua linha de log. Compartilhado pelo GlobalExceptionHandler (erros dentro do MVC) e pelo
 * ProblemErrorController (erros que o servlet container encaminha para /error, ADR 0007), para
 * que os dois mascarem erros de banco do mesmo jeito. O CommittedResponseFailureFilter usa a mesma
 * linha de log para falhas depois do envio da resposta.
 */
@Slf4j
final class InternalErrors {

    static final String DETAIL = "An unexpected error occurred.";

    /**
     * Most throwables {@link #find} visits before it gives up. Real chains have a handful of
     * nodes; a bigger graph is either built to attack the logger or broken (a getCause() that
     * returns a new object on every call), so it is treated like a database error: masked.
     *
     * <p>PT: Máximo de throwables que o {@link #find} visita antes de desistir. Cadeias reais têm
     * poucos nós; um grafo maior foi montado para atacar o log ou está quebrado (um getCause() que
     * devolve um objeto novo a cada chamada), então é tratado como erro de banco: mascarado.
     */
    static final int MAX_NODES = 1024;

    private static final String COMMITTED = " responseCommitted=true";

    private InternalErrors() {
    }

    /**
     * Logs the failure under a new errorId and returns the generic 500 body carrying that id.
     * Never throws (only a fatal JVM error passes, see rethrowIfFatal): it also runs inside the
     * container's error dispatch, which has no fallback.
     *
     * <p>PT: Registra a falha no log com um novo errorId e devolve o corpo 500 genérico com esse id.
     * Nunca lança exceção (só um erro fatal da JVM passa, veja rethrowIfFatal): também roda dentro
     * do error dispatch do container, que não tem plano B.
     *
     * @param ex the failure, or {@code null} when the container reports a 5xx without one
     */
    static ProblemDetail problem(Throwable ex, String path) {
        var errorId = UUID.randomUUID();
        log(errorId, ex, "");
        var problem = ProblemFactory.create(HttpStatus.INTERNAL_SERVER_ERROR, Slugs.INTERNAL_ERROR, DETAIL, path);
        problem.setProperty("errorId", errorId.toString());
        return problem;
    }

    /**
     * Logs a failure that escaped after the response was already committed. The container can then
     * only include /error into the half-sent response, and that include does not reach
     * ProblemErrorController's logging (CommittedResponseFailureFilter explains why), so this is the
     * only log line the failure gets. Same masking and same errorId format as {@link #problem}, so
     * one search finds both; the errorId is never sent (there is no body left to carry it) and
     * {@code responseCommitted=true} tells the two apart. Never throws, like {@link #problem}.
     * GlobalExceptionHandler calls it too, for a framework error or a client disconnect inside MVC
     * after commit (any other failure there is rethrown and reaches the filter). A client
     * disconnect gets the short DEBUG line of {@link #logClientDisconnect} instead.
     *
     * <p>PT: Registra uma falha que escapou depois que a resposta já tinha sido enviada (committed).
     * O container então só consegue incluir o /error na resposta já meio enviada, e esse include não
     * chega ao log do ProblemErrorController (o CommittedResponseFailureFilter explica o porquê),
     * então esta é a única linha de log que a falha recebe. Mesmo mascaramento e mesmo formato de
     * errorId do {@link #problem}, para que uma busca encontre os dois; o errorId nunca é enviado
     * (não sobra corpo para levá-lo) e {@code responseCommitted=true} distingue os dois casos. Nunca
     * lança exceção, como o {@link #problem}. O GlobalExceptionHandler também o chama, para um erro
     * do framework ou uma desconexão do cliente dentro do MVC depois do envio (qualquer outra falha
     * ali é relançada e chega ao filtro). Uma desconexão do cliente recebe, no lugar, a linha DEBUG
     * curta do {@link #logClientDisconnect}.
     */
    static void logCommitted(Throwable ex) {
        var errorId = UUID.randomUUID();
        if (isClientDisconnect(ex)) {
            logDisconnect(errorId, ex, COMMITTED);
            return;
        }
        log(errorId, ex, COMMITTED);
    }

    /**
     * Logs a client that went away (see {@link #isClientDisconnect}) as one DEBUG line: errorId and
     * exception class, never the message or the stack trace. DEBUG because it is the client's doing
     * (closed app, lost network), nobody can act on it, and an anonymous client can repeat it at
     * will: at ERROR with a stack trace every reset would write ~100 lines and drown real failures.
     * Spring logs its own disconnected-client line at DEBUG too. Never throws.
     *
     * <p>PT: Registra um cliente que foi embora (veja {@link #isClientDisconnect}) como uma linha
     * DEBUG: errorId e classe da exceção, nunca a mensagem nem o stack trace. DEBUG porque é obra do
     * cliente (app fechado, rede perdida), ninguém pode agir sobre isso, e um cliente anônimo pode
     * repetir à vontade: em ERROR com stack trace cada reset escreveria ~100 linhas e afogaria as
     * falhas reais. O Spring registra a própria linha de cliente desconectado em DEBUG também. Nunca
     * lança exceção.
     */
    static void logClientDisconnect(Throwable ex) {
        logDisconnect(UUID.randomUUID(), ex, "");
    }

    /**
     * True when the failure only means the client closed or reset the connection: Tomcat's
     * ClientAbortException or Spring's AsyncRequestNotUsableException as the failure itself or
     * somewhere along its cause chain. Suppressed exceptions are not searched for it: a disconnect
     * attached as suppressed (a close() that failed because the client was gone) is a side effect
     * of the real failure, and must not downgrade that failure to a DEBUG line. Decided by type,
     * never by message: messages change between versions and a database error can say
     * "Connection reset" too. A database error anywhere in the graph (causes and suppressed, the
     * same search as the masking) wins, so a driver failure stays a masked ERROR. Narrower than
     * Spring's DisconnectedClientHelper on purpose: java.io.EOFException is also thrown by file
     * and deserialization bugs, and Jetty/Netty types never occur on Tomcat. Never throws; a graph
     * that cannot be inspected is not a disconnect.
     *
     * <p>PT: Verdadeiro quando a falha só significa que o cliente fechou ou resetou a conexão: o
     * ClientAbortException do Tomcat ou o AsyncRequestNotUsableException do Spring como a própria
     * falha ou em algum ponto da sua cadeia de causas. As exceções suprimidas não são procuradas:
     * uma desconexão anexada como suprimida (um close() que falhou porque o cliente já tinha ido
     * embora) é efeito colateral da falha real e não pode rebaixar essa falha para uma linha DEBUG.
     * Decidido pelo tipo, nunca pela mensagem: mensagens mudam entre versões e um erro de banco
     * também pode dizer "Connection reset". Um erro de banco em qualquer ponto do grafo (causas e
     * suprimidas, a mesma busca do mascaramento) tem prioridade, então uma falha do driver continua
     * um ERROR mascarado. Mais restrito que o DisconnectedClientHelper do Spring de propósito:
     * java.io.EOFException também é lançada por bugs de arquivo e desserialização, e tipos do
     * Jetty/Netty nunca aparecem no Tomcat. Nunca lança exceção; um grafo que não pode ser
     * inspecionado não é desconexão.
     */
    static boolean isClientDisconnect(Throwable ex) {
        if (ex == null) {
            return false;
        }
        try {
            return find(ex, InternalErrors::isDatabaseError) == null
                    && findInCauseChain(ex, InternalErrors::isDisconnectType) != null;
        } catch (Throwable traversalFailure) {
            rethrowIfFatal(traversalFailure);
            return false;
        }
    }

    private static boolean isDisconnectType(Throwable ex) {
        return ex instanceof ClientAbortException || ex instanceof AsyncRequestNotUsableException;
    }

    private static void logDisconnect(UUID errorId, Throwable ex, String suffix) {
        log.debug("Client disconnected errorId={} exception={}{}", errorId, ex.getClass().getName(), suffix);
    }

    /**
     * @param suffix appended to every line as-is; a fixed text chosen by this class, never input
     *               (PT: anexado a toda linha como está; um texto fixo escolhido por esta classe,
     *               nunca entrada do usuário)
     */
    private static void log(UUID errorId, Throwable ex, String suffix) {
        if (ex == null) {
            log.error("Unexpected error errorId={} exception=none{}", errorId, suffix);
            return;
        }
        boolean database;
        String constraint;
        try {
            database = find(ex, InternalErrors::isDatabaseError) != null;
            constraint = database ? constraintName(ex) : null;
        } catch (Throwable traversalFailure) {
            rethrowIfFatal(traversalFailure);
            // A Throwable whose getCause()/getSuppressed() misbehaves, or a graph bigger than
            // MAX_NODES, cannot be inspected safely, so it is treated as possibly carrying database
            // values: masked, never printed.
            // PT: Um Throwable cujo getCause()/getSuppressed() se comporta mal, ou um grafo maior
            //     que MAX_NODES, não pode ser inspecionado com segurança, então é tratado como
            //     possível portador de valores do banco: mascarado, nunca impresso.
            database = true;
            constraint = null;
        }
        if (database) {
            logMasked(errorId, ex, constraint, suffix);
            return;
        }
        try {
            // The full exception stays in the server log; the client only gets the id to report.
            // PT: A exceção completa fica no log do servidor; o cliente recebe só o id para
            //     reportar.
            log.error("Unexpected error errorId={}{}", errorId, suffix, ex);
        } catch (Throwable loggingFailure) {
            rethrowIfFatal(loggingFailure);
            // Printing the stack trace runs the throwable's own code (getStackTrace, toString,
            // getMessage) and the logger walks the chain recursively; if that fails, the one-line
            // form still records the id.
            // PT: Imprimir o stack trace executa código do próprio throwable (getStackTrace,
            //     toString, getMessage), e o logger percorre a cadeia recursivamente; se isso falhar,
            //     a forma de uma linha ainda registra o id.
            logMasked(errorId, ex, null, suffix);
        }
    }

    /**
     * Driver messages and their cause chain quote column values (PostgreSQL:
     * "Key (email)=(...) already exists"), so neither the message nor the stack trace is logged.
     * The constraint name is a schema identifier and says what failed.
     *
     * <p>PT: As mensagens do driver e a cadeia de causas delas citam valores de colunas
     * (PostgreSQL: "Key (email)=(...) already exists"), então nem a mensagem nem o stack trace vão
     * para o log. O nome da constraint é um identificador do esquema e diz o que falhou.
     */
    private static void logMasked(UUID errorId, Throwable ex, String constraint, String suffix) {
        log.error("Unexpected data access error errorId={} exception={} constraint={}{}",
                errorId, ex.getClass().getName(), constraint, suffix);
    }

    /**
     * Policy for failures while inspecting or logging: everything is absorbed, so the error path
     * keeps answering, except a VirtualMachineError other than StackOverflowError. A stack
     * overflow is local to this thread and is over once the stack has unwound to the catch, so
     * answering afterwards is safe. OutOfMemoryError, InternalError and UnknownError describe the
     * whole JVM; hiding them would keep a broken process serving requests.
     *
     * <p>PT: Política para falhas durante a inspeção ou o log: tudo é absorvido, para que o caminho
     * de erro continue respondendo, exceto um VirtualMachineError que não seja StackOverflowError.
     * Um estouro de pilha é local a esta thread e acaba quando a pilha volta até o catch, então
     * responder depois é seguro. OutOfMemoryError, InternalError e UnknownError descrevem a JVM
     * inteira; escondê-los manteria um processo quebrado atendendo requisições.
     */
    private static void rethrowIfFatal(Throwable failure) {
        if (failure instanceof VirtualMachineError fatal && !(failure instanceof StackOverflowError)) {
            throw fatal;
        }
    }

    static boolean isDatabaseError(Throwable ex) {
        return ex instanceof DataAccessException
                || ex instanceof SQLException
                || ex instanceof JDBCException
                || ex instanceof PersistenceException;
    }

    static String constraintName(Throwable ex) {
        var violation = find(ex,
                current -> current instanceof org.hibernate.exception.ConstraintViolationException);
        return violation != null
                ? ((org.hibernate.exception.ConstraintViolationException) violation).getConstraintName()
                : null;
    }

    /**
     * First throwable reachable from {@code root} that matches, looking at causes and at every
     * suppressed exception (and their causes). A database error can hide in either place: a
     * try-with-resources whose close() fails attaches it as suppressed. Iterative with an identity
     * set and at most {@link #MAX_NODES} visits, so a cycle (A -> B -> A, a self-cause, suppressed
     * loops), a very deep chain or a getCause() that invents a new object on every call can
     * neither loop forever nor overflow the stack.
     *
     * <p>PT: Primeiro throwable alcançável a partir de {@code root} que satisfaz o teste, olhando as
     * causas e toda exceção suprimida (e as causas delas). Um erro de banco pode se esconder em
     * qualquer um dos dois lugares: um try-with-resources cujo close() falha o anexa como suprimido.
     * Iterativo, com um conjunto por identidade e no máximo {@link #MAX_NODES} visitas, então um
     * ciclo (A -> B -> A, uma exceção que é causa de si mesma, laços de suprimidas), uma cadeia muito
     * profunda ou um getCause() que inventa um objeto novo a cada chamada não pode nem rodar para
     * sempre nem estourar a pilha.
     *
     * @return the first match, or {@code null} if none
     * @throws TraversalLimitExceeded if more than {@link #MAX_NODES} throwables are reachable
     */
    static Throwable find(Throwable root, Predicate<Throwable> matches) {
        Set<Throwable> seen = Collections.newSetFromMap(new IdentityHashMap<>());
        var pending = new ArrayDeque<Throwable>();
        if (root != null) {
            pending.push(root);
        }
        while (!pending.isEmpty()) {
            var current = pending.pop();
            if (!seen.add(current)) {
                continue;
            }
            if (seen.size() > MAX_NODES) {
                throw new TraversalLimitExceeded();
            }
            if (matches.test(current)) {
                return current;
            }
            for (var suppressed : current.getSuppressed()) {
                if (suppressed != null) {
                    pending.push(suppressed);
                }
            }
            var cause = current.getCause();
            if (cause != null) {
                // Pushed last so it is popped first: the cause chain is explored before the
                // suppressed exceptions (depth-first). The order does not change what is found,
                // only which match comes first.
                // PT: Empilhada por último para ser desempilhada primeiro: a cadeia de causas é
                //     explorada antes das exceções suprimidas (em profundidade). A ordem não muda o
                //     que é encontrado, só qual ocorrência vem primeiro.
                pending.push(cause);
            }
        }
        return null;
    }

    /**
     * First throwable along {@code root}'s getCause() chain (root included) that matches; suppressed
     * exceptions are skipped. Same guards as {@link #find}: an identity set stops a cycle or a
     * self-cause, and more than {@link #MAX_NODES} links throw.
     *
     * <p>PT: Primeiro throwable ao longo da cadeia de getCause() de {@code root} (incluindo o root)
     * que satisfaz o teste; as exceções suprimidas são ignoradas. As mesmas proteções do
     * {@link #find}: um conjunto por identidade para um ciclo ou uma exceção que é causa de si
     * mesma, e mais de {@link #MAX_NODES} elos lançam exceção.
     *
     * @return the first match, or {@code null} if none
     * @throws TraversalLimitExceeded if the chain has more than {@link #MAX_NODES} links
     */
    static Throwable findInCauseChain(Throwable root, Predicate<Throwable> matches) {
        Set<Throwable> seen = Collections.newSetFromMap(new IdentityHashMap<>());
        for (var current = root; current != null && seen.add(current); current = current.getCause()) {
            if (seen.size() > MAX_NODES) {
                throw new TraversalLimitExceeded();
            }
            if (matches.test(current)) {
                return current;
            }
        }
        return null;
    }

    /**
     * Thrown by {@link #find} when the graph is too big to inspect. No stack trace and no cause:
     * it only signals "give up", and log() treats it as a database error (masked).
     *
     * <p>PT: Lançada pelo {@link #find} quando o grafo é grande demais para inspecionar. Sem stack
     * trace e sem causa: só sinaliza "desistir", e o log() a trata como erro de banco (mascarado).
     */
    static final class TraversalLimitExceeded extends RuntimeException {

        TraversalLimitExceeded() {
            super("More than " + MAX_NODES + " throwables reachable", null, false, false);
        }
    }
}
