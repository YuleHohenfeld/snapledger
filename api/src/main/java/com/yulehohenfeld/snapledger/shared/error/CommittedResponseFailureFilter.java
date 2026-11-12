package com.yulehohenfeld.snapledger.shared.error;

import java.io.IOException;

import jakarta.servlet.Filter;
import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.ServletRequest;
import jakarta.servlet.ServletResponse;

import org.springframework.core.Ordered;
import org.springframework.core.annotation.Order;
import org.springframework.stereotype.Component;

/**
 * Logs a failure that escapes after the response was committed, the one case where /error never
 * logs it (ADR 0007 point 6). Tomcat cannot forward a committed response, so it INCLUDEs /error
 * instead. Chain 2 permits only the ERROR dispatch to /error, so an anonymous include is denied
 * before ProblemErrorController runs; an authenticated include reaches the controller, but against
 * a real Tomcat it logged nothing either (ContainerErrorDispatchIntegrationTest reproduces both
 * cases). Tomcat's own copy is turned off in
 * logback-spring.xml. Without this filter the failure would leave no trace at all. Widening the
 * permitAll to INCLUDE would not fix the authenticated case and would open /error to any future
 * include, so the failure is logged here instead.
 *
 * <p>When the response is not committed it only rethrows: the container then forwards to /error,
 * where InternalErrors logs the failure with the errorId sent to the client. Logging here too
 * would log it twice. Inside Spring MVC after commit, the catch-all of GlobalExceptionHandler
 * rethrows the failure without logging it, so it is logged here and Tomcat aborts the connection;
 * a framework error is logged and handled by GlobalExceptionHandler and never gets here. A client
 * that went away is one DEBUG line (InternalErrors.logClientDisconnect), not an ERROR.
 *
 * <p>Highest precedence, so it wraps every other filter, including Spring Security's chain (a
 * failure inside a security filter is seen too). A plain Filter bean is registered by Boot for
 * REQUEST dispatches only, which is the one dispatch where a failure first escapes while every
 * endpoint is synchronous. The first async endpoint must also register it for ASYNC (ADR 0007
 * point 6).
 *
 * <p>PT: Registra uma falha que escapa depois que a resposta foi enviada (committed), o único caso
 * em que o /error nunca a registra (ADR 0007 ponto 6). O Tomcat não consegue fazer forward de uma
 * resposta já enviada, então faz um INCLUDE do /error. A cadeia 2 só permite o dispatch ERROR
 * para /error, então um include anônimo é negado antes de o ProblemErrorController rodar; um
 * include autenticado chega ao controller, mas contra um Tomcat de verdade também não registrou
 * nada (o ContainerErrorDispatchIntegrationTest reproduz os dois casos). A cópia do próprio
 * Tomcat está desligada no logback-spring.xml. Sem este filtro a falha não deixaria rastro
 * nenhum. Abrir o permitAll para INCLUDE não resolveria o caso autenticado e abriria o /error
 * para qualquer include futuro, então a falha é registrada aqui.
 *
 * <p>PT: Quando a resposta ainda não foi enviada, ele só relança: o container então faz forward
 * para /error, onde o InternalErrors registra a falha com o errorId enviado ao cliente. Registrar
 * aqui também registraria duas vezes. Dentro do Spring MVC depois do envio, o pega-tudo do
 * GlobalExceptionHandler relança a falha sem registrá-la, então ela é registrada aqui e o Tomcat
 * aborta a conexão; um erro do framework é registrado e tratado pelo GlobalExceptionHandler e nunca
 * chega aqui. Um cliente que foi embora vira uma linha DEBUG (InternalErrors.logClientDisconnect),
 * não um ERROR.
 *
 * <p>PT: Precedência máxima, para envolver todos os outros filtros, inclusive a cadeia do Spring
 * Security (uma falha dentro de um filtro de segurança também é vista). Um Filter simples é
 * registrado pelo Boot só para dispatches REQUEST, que é o único dispatch em que uma falha escapa
 * pela primeira vez enquanto todo endpoint é síncrono. O primeiro endpoint assíncrono precisa
 * registrá-lo também para ASYNC (ADR 0007 ponto 6).
 */
@Component
@Order(Ordered.HIGHEST_PRECEDENCE)
public class CommittedResponseFailureFilter implements Filter {

    @Override
    public void doFilter(ServletRequest request, ServletResponse response, FilterChain chain)
            throws IOException, ServletException {
        try {
            chain.doFilter(request, response);
        } catch (Throwable failure) {
            if (response.isCommitted()) {
                InternalErrors.logCommitted(failure);
            }
            // Always rethrown: the container still has to finish the response (close the
            // connection) and its own handling must stay the same.
            // PT: Sempre relançada: o container ainda precisa terminar a resposta (fechar a
            //     conexão), e o tratamento dele precisa continuar o mesmo.
            throw failure;
        }
    }
}
