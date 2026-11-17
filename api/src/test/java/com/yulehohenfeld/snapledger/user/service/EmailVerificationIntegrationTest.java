package com.yulehohenfeld.snapledger.user.service;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.UUID;
import java.util.concurrent.Executors;

import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.context.annotation.Import;
import org.springframework.http.HttpHeaders;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.web.servlet.MockMvc;

import tools.jackson.databind.json.JsonMapper;

import com.yulehohenfeld.snapledger.support.AccountApi;
import com.yulehohenfeld.snapledger.support.FakeEmailSender;
import com.yulehohenfeld.snapledger.support.RefreshTokenFixtures;
import com.yulehohenfeld.snapledger.support.TestJwtSecret;
import com.yulehohenfeld.snapledger.support.TestcontainersConfiguration;

/**
 * Email verification through the real endpoints on a real PostgreSQL: the code sent by register,
 * the confirmation, the resend limits, the failed attempt that stays counted, and the reset
 * verifying the email too. MockMvc, never a port; the mail is captured by a fake sender.
 *
 * <p>PT: Verificação de email pelos endpoints reais num PostgreSQL real: o código enviado pelo
 * cadastro, a confirmação, os limites de reenvio, a tentativa falha que continua contada, e a
 * redefinição verificando o email também. MockMvc, nunca uma porta; o email é capturado por um
 * sender falso.
 * Notes: docs/code-notes/user.md#emailverificationservice
 */
@SpringBootTest
@AutoConfigureMockMvc
@Import({TestcontainersConfiguration.class, TestJwtSecret.class})
class EmailVerificationIntegrationTest {

    static final JsonMapper JSON = JsonMapper.builder().build();

    @Autowired
    MockMvc mvc;

    @Autowired
    JdbcTemplate jdbc;

    @Autowired
    FakeEmailSender mail;

    final String password = "pw-" + UUID.randomUUID();
    AccountApi api;
    RefreshTokenFixtures fixtures;

    @BeforeEach
    void setUp() {
        api = new AccountApi(mvc, mail);
        fixtures = new RefreshTokenFixtures(jdbc);
    }

    @AfterEach
    void cleanUp() {
        fixtures.cleanUp(Executors.newSingleThreadExecutor());
    }

    @Test
    void registerEmailsACodeAndConfirmingItMarksTheEmailVerified() throws Exception {
        var email = fixtures.uniqueEmail();
        var session = api.register(email, password);
        var access = session.get("tokens").get("accessToken").asString();
        assertThat(session.get("user").get("emailVerified").asBoolean()).isFalse();

        var confirmed = api.confirmVerification(access, api.verificationCodeOf(email));

        assertThat(confirmed.getStatus()).isEqualTo(200);
        var profile = JSON.readTree(confirmed.getContentAsString());
        assertThat(profile.get("emailVerified").asBoolean()).isTrue();
        assertThat(profile.get("email").asString()).isEqualTo(email);
        assertThat(JSON.readTree(api.me(access).getContentAsString()).get("emailVerified").asBoolean()).isTrue();
    }

    @Test
    void aSecondConfirmOfAVerifiedAccountReturnsTheProfileAndAskingForACodeSendsNothing() throws Exception {
        var email = fixtures.uniqueEmail();
        var access = api.register(email, password).get("tokens").get("accessToken").asString();
        var code = api.verificationCodeOf(email);
        api.confirmVerification(access, code);

        var again = api.confirmVerification(access, "000000");
        var resend = api.sendVerification(access);

        assertThat(again.getStatus()).isEqualTo(200);
        assertThat(JSON.readTree(again.getContentAsString()).get("emailVerified").asBoolean()).isTrue();
        assertThat(resend.getStatus()).isEqualTo(202);
        assertThat(resend.getContentAsString()).isEmpty();
        assertThat(api.countSubject(email, "verification")).isEqualTo(1);
    }

    // Register already sent a code, so an immediate resend is inside the 60 s cooldown.
    // PT: O cadastro já enviou um código, então um reenvio imediato está dentro do cooldown de 60 s.
    @Test
    void anImmediateResendIs429WithRetryAfterAndSendsNothing() throws Exception {
        var email = fixtures.uniqueEmail();
        var access = api.register(email, password).get("tokens").get("accessToken").asString();

        var resend = api.sendVerification(access);

        assertThat(resend.getStatus()).isEqualTo(429);
        assertThat(resend.getHeader(HttpHeaders.RETRY_AFTER)).isEqualTo("60");
        assertThat(resend.getContentAsString()).contains("urn:snapledger:problem:too-many-requests");
        assertThat(api.countSubject(email, "verification")).isEqualTo(1);
    }

    @Test
    void aResendAfterTheCooldownEmailsANewCodeThatReplacesTheOldOne() throws Exception {
        var email = fixtures.uniqueEmail();
        var access = api.register(email, password).get("tokens").get("accessToken").asString();
        var first = api.verificationCodeOf(email);
        // Moves the first send 2 minutes into the past instead of sleeping.
        // PT: Move o primeiro envio 2 minutos para o passado em vez de dormir.
        jdbc.update("""
                update account_codes set sent_at = sent_at - interval '2 minutes',
                    window_started_at = window_started_at - interval '2 minutes',
                    expires_at = expires_at - interval '2 minutes'
                where purpose = 'EMAIL_VERIFICATION' and user_id = (select id from users where email = ?)
                """, email);

        assertThat(api.sendVerification(access).getStatus()).isEqualTo(202);

        assertThat(api.countSubject(email, "verification")).isEqualTo(2);
        var second = api.verificationCodeOf(email);
        if (!second.equals(first)) {
            assertThat(api.confirmVerification(access, first).getStatus()).isEqualTo(400);
        }
        assertThat(api.confirmVerification(access, second).getStatus()).isEqualTo(200);
    }

    // The GATE for this endpoint: the attempt stays counted after the 400.
    // PT: O PORTÃO deste endpoint: a tentativa continua contada depois do 400.
    @Test
    void aWrongCodeIs400AndLeavesTheAttemptAndTheFailureBudgetCounted() throws Exception {
        var email = fixtures.uniqueEmail();
        var access = api.register(email, password).get("tokens").get("accessToken").asString();
        var wrong = api.verificationCodeOf(email).equals("000000") ? "000001" : "000000";

        var response = api.confirmVerification(access, wrong);

        assertThat(response.getStatus()).isEqualTo(400);
        assertThat(response.getContentAsString()).contains("urn:snapledger:problem:invalid-code");
        var row = jdbc.queryForMap("""
                select c.attempts, c.failed_in_window from account_codes c join users u on u.id = c.user_id
                where u.email = ? and c.purpose = 'EMAIL_VERIFICATION'
                """, email);
        assertThat(row.get("attempts")).isEqualTo(1);
        assertThat(row.get("failed_in_window")).isEqualTo(1);
        assertThat(JSON.readTree(api.me(access).getContentAsString()).get("emailVerified").asBoolean()).isFalse();
    }

    @Test
    void bothEndpointsRequireAToken() throws Exception {
        assertThat(api.sendVerification("not-a-jwt").getStatus()).isEqualTo(401);
        assertThat(api.confirmVerification("not-a-jwt", "042917").getStatus()).isEqualTo(401);
    }

    // The reset code proves access to the email as well, so it verifies it.
    // PT: O código da redefinição também prova o acesso ao email, então ele o verifica.
    @Test
    void aSuccessfulPasswordResetMarksTheEmailVerified() throws Exception {
        var email = fixtures.uniqueEmail();
        api.register(email, password);
        api.requestReset(email);

        var confirmed = api.confirmReset(api.resetToken(email, api.resetCodeOf(email)), "new-" + UUID.randomUUID());

        assertThat(confirmed.getStatus()).isEqualTo(204);
        assertThat(jdbc.queryForObject("select email_verified_at is not null from users where email = ?",
                Boolean.class, email)).isTrue();
    }
}
