package com.yulehohenfeld.snapledger.shared.email;

import java.util.concurrent.Executor;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.scheduling.concurrent.ThreadPoolTaskExecutor;

/** The bounded executor that sends email off the request thread: 1 to 2 threads, 100 queued.
 *  PT: O executor limitado que envia email fora da thread da requisição: 1 a 2 threads, 100 na fila.
 *  Notes: docs/code-notes/email.md#mailexecutorconfig */
@Configuration(proxyBeanMethods = false)
public class MailExecutorConfig {

    public static final String MAIL_EXECUTOR = "mailExecutor";

    @Bean(MAIL_EXECUTOR)
    Executor mailExecutor() {
        var executor = new ThreadPoolTaskExecutor();
        executor.setCorePoolSize(1);
        executor.setMaxPoolSize(2);
        executor.setQueueCapacity(100);
        executor.setThreadNamePrefix("mail-");
        // A full queue rejects (default AbortPolicy); MailDispatcher logs it and moves on.
        // PT: Fila cheia rejeita (AbortPolicy padrão); o MailDispatcher registra e segue.
        executor.setWaitForTasksToCompleteOnShutdown(true);
        executor.setAwaitTerminationSeconds(10);
        return executor;
    }
}
