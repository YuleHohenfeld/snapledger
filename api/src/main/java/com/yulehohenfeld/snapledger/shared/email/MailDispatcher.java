package com.yulehohenfeld.snapledger.shared.email;

import java.util.concurrent.Executor;

import lombok.extern.slf4j.Slf4j;

import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.stereotype.Component;
import org.springframework.transaction.support.TransactionSynchronization;
import org.springframework.transaction.support.TransactionSynchronizationManager;

/**
 * Sends email best effort: after the caller's transaction commits (or at once with none), on the
 * bounded executor. Never throws; a failure logs one line with the exception class only.
 *
 * <p>PT: Envia email do melhor jeito possível: depois do commit da transação de quem chama (ou na
 * hora, se não houver), no executor limitado. Nunca lança; uma falha registra uma linha só com a
 * classe da exceção.
 * Notes: docs/code-notes/email.md#maildispatcher
 */
@Slf4j
@Component
public class MailDispatcher {

    private final EmailSender sender;
    private final Executor executor;

    public MailDispatcher(EmailSender sender, @Qualifier(MailExecutorConfig.MAIL_EXECUTOR) Executor executor) {
        this.sender = sender;
        this.executor = executor;
    }

    public void sendAfterCommit(EmailMessage message) {
        try {
            if (TransactionSynchronizationManager.isSynchronizationActive()) {
                TransactionSynchronizationManager.registerSynchronization(new TransactionSynchronization() {
                    @Override
                    public void afterCommit() {
                        submit(message);
                    }
                });
            } else {
                submit(message);
            }
        } catch (RuntimeException e) {
            logFailure(e);
        }
    }

    private void submit(EmailMessage message) {
        try {
            executor.execute(() -> deliver(message));
        } catch (RuntimeException e) {
            // Queue full or executor stopped (TaskRejectedException). PT: Fila cheia ou executor parado.
            logFailure(e);
        }
    }

    private void deliver(EmailMessage message) {
        try {
            sender.send(message);
        } catch (RuntimeException e) {
            logFailure(e);
        }
    }

    // Class only: a mail exception message can quote the recipient or a server reply.
    // PT: Só a classe: a mensagem de uma exceção de email pode citar o destinatário ou a resposta do servidor.
    private static void logFailure(RuntimeException e) {
        log.warn("Email not sent: {}", e.getClass().getName());
    }
}
