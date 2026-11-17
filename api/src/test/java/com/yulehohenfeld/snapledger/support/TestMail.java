package com.yulehohenfeld.snapledger.support;

import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Primary;

import com.yulehohenfeld.snapledger.shared.email.MailDispatcher;

/**
 * Keeps every test context from sending real email: a {@link FakeEmailSender} bean and a primary
 * {@link MailDispatcher} that delivers on the calling thread, right after commit, so a test reads
 * the code with no waiting. {@link TestAccountCodeSecret} imports it, so every context that binds
 * the secrets has it and the context cache key stays the same.
 *
 * <p>PT: Impede que qualquer contexto de teste envie email de verdade: um bean {@link FakeEmailSender}
 * e um {@link MailDispatcher} primário que entrega na própria thread, logo depois do commit, então o
 * teste lê o código sem esperar. O {@link TestAccountCodeSecret} o importa, então todo contexto que
 * lê os segredos o tem e a chave do cache de contextos continua a mesma.
 */
@TestConfiguration(proxyBeanMethods = false)
public class TestMail {

    @Bean
    @Primary
    FakeEmailSender fakeEmailSender() {
        return new FakeEmailSender();
    }

    @Bean
    @Primary
    MailDispatcher synchronousMailDispatcher(FakeEmailSender sender) {
        return new MailDispatcher(sender, Runnable::run);
    }
}
