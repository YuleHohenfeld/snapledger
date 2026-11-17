package com.yulehohenfeld.snapledger.shared.email;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatCode;

import java.util.concurrent.Executor;
import java.util.concurrent.RejectedExecutionException;
import java.util.concurrent.atomic.AtomicInteger;

import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.springframework.boot.test.system.CapturedOutput;
import org.springframework.boot.test.system.OutputCaptureExtension;
import org.springframework.mail.MailSendException;
import org.springframework.transaction.support.TransactionSynchronizationManager;
import org.springframework.transaction.support.TransactionSynchronization;

/**
 * Best effort: runs after commit, never throws, logs the exception class and nothing else.
 *
 * <p>PT: Melhor esforço: roda depois do commit, nunca lança, registra a classe da exceção e mais nada.
 */
@ExtendWith(OutputCaptureExtension.class)
class MailDispatcherTest {

    static final String RECIPIENT = "dispatch.secret@example.com";
    static final String BODY = "code 987654";
    final EmailMessage message = new EmailMessage(RECIPIENT, "Subject", BODY, "<p>" + BODY + "</p>");
    final Executor direct = Runnable::run;

    @AfterEach
    void clearSynchronization() {
        if (TransactionSynchronizationManager.isSynchronizationActive()) {
            TransactionSynchronizationManager.clearSynchronization();
        }
    }

    @Test
    void sendsAtOnceWhenThereIsNoTransaction() {
        var sent = new AtomicInteger();

        new MailDispatcher(m -> sent.incrementAndGet(), direct).sendAfterCommit(message);

        assertThat(sent).hasValue(1);
    }

    @Test
    void waitsForTheCommitInsideATransactionAndDropsTheMailOnRollback() {
        var sent = new AtomicInteger();
        var dispatcher = new MailDispatcher(m -> sent.incrementAndGet(), direct);
        TransactionSynchronizationManager.initSynchronization();

        dispatcher.sendAfterCommit(message);
        assertThat(sent).hasValue(0);

        TransactionSynchronizationManager.getSynchronizations().forEach(TransactionSynchronization::afterCommit);
        assertThat(sent).hasValue(1);
    }

    @Test
    void aSenderFailureIsLoggedAsOneLineWithTheClassOnly(CapturedOutput output) {
        var dispatcher = new MailDispatcher(m -> {
            throw new MailSendException("550 rejected " + RECIPIENT + " " + BODY);
        }, direct);

        assertThatCode(() -> dispatcher.sendAfterCommit(message)).doesNotThrowAnyException();

        assertThat(output.getAll())
                .contains("Email not sent: org.springframework.mail.MailSendException")
                .doesNotContain(RECIPIENT).doesNotContain(BODY).doesNotContain("550");
        assertThat(output.getAll().lines().filter(l -> l.contains("Email not sent")).count()).isEqualTo(1);
    }

    @Test
    void aRejectedTaskIsLoggedAndNeverThrown(CapturedOutput output) {
        Executor full = r -> {
            throw new RejectedExecutionException("queue full for " + RECIPIENT);
        };

        assertThatCode(() -> new MailDispatcher(m -> { }, full).sendAfterCommit(message)).doesNotThrowAnyException();

        assertThat(output.getAll()).contains("Email not sent: java.util.concurrent.RejectedExecutionException")
                .doesNotContain(RECIPIENT);
    }
}
