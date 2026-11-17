package com.yulehohenfeld.snapledger.auth.service;

import static com.yulehohenfeld.snapledger.support.AccountApi.newIp;
import static com.yulehohenfeld.snapledger.support.LockWaits.await;
import static com.yulehohenfeld.snapledger.support.LockWaits.awaitBlockedTransactions;
import static org.assertj.core.api.Assertions.assertThat;
import static org.junit.jupiter.api.Assumptions.assumeFalse;

import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.TreeMap;
import java.util.UUID;
import java.util.concurrent.Callable;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.TimeUnit;
import java.util.regex.Pattern;

import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.system.CapturedOutput;
import org.springframework.boot.test.system.OutputCaptureExtension;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.context.annotation.Import;
import org.springframework.http.HttpHeaders;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.mock.web.MockHttpServletResponse;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;

import tools.jackson.databind.json.JsonMapper;

import com.yulehohenfeld.snapledger.shared.ratelimit.RateLimitProperties;
import com.yulehohenfeld.snapledger.support.AccountApi;
import com.yulehohenfeld.snapledger.support.FakeEmailSender;
import com.yulehohenfeld.snapledger.support.RefreshTokenFixtures;
import com.yulehohenfeld.snapledger.support.TestJwtSecret;
import com.yulehohenfeld.snapledger.support.TestPasswordHashes;
import com.yulehohenfeld.snapledger.support.TestcontainersConfiguration;

/**
 * THE GATE of Phase 1.5 step 2, through the real endpoints on a real PostgreSQL: the full reset
 * flow, the same answer for known and unknown emails, a wrong code that stays counted (attempts AND
 * failure budget), exhausted codes and budgets, parallel confirms, a reset racing a refresh and a
 * login, the per-IP and per-email limits, and a clean log. MockMvc, never a port; the mail is
 * captured by a fake sender, synchronously.
 *
 * <p>PT: O PORTÃO do passo 2 da Fase 1.5, pelos endpoints reais num PostgreSQL real: o fluxo
 * completo da redefinição, a mesma resposta para emails conhecidos e desconhecidos, um código errado
 * que continua contado (tentativas E orçamento de falhas), códigos e orçamentos esgotados, confirmações
 * em paralelo, uma redefinição disputando com um refresh e com um login, os limites por IP e por
 * email, e um log limpo. MockMvc, nunca uma porta; o email é capturado por um sender falso, de forma
 * síncrona.
 * Notes: docs/code-notes/auth.md#passwordresetservice
 */
@ExtendWith(OutputCaptureExtension.class)
@SpringBootTest
@AutoConfigureMockMvc
@Import({TestcontainersConfiguration.class, TestJwtSecret.class})
class PasswordResetIntegrationTest {

    static final JsonMapper JSON = JsonMapper.builder().build();

    @Autowired
    MockMvc mvc;

    @Autowired
    JdbcTemplate jdbc;

    @Autowired
    FakeEmailSender mail;

    @Autowired
    PlatformTransactionManager transactionManager;

    @Autowired
    RateLimitProperties limits;

    // Random per test instance: no literal password in tests.
    // PT: Aleatória por instância de teste: nenhuma senha literal nos testes.
    final String password = "pw-" + UUID.randomUUID();
    final String newPassword = "new-" + UUID.randomUUID();
    AccountApi api;
    RefreshTokenFixtures fixtures;
    ExecutorService threads;

    @BeforeEach
    void setUp() {
        api = new AccountApi(mvc, mail);
        fixtures = new RefreshTokenFixtures(jdbc);
        threads = Executors.newFixedThreadPool(3);
    }

    @AfterEach
    void cleanUp() {
        fixtures.cleanUp(threads);
    }

    // --- the flow ---
    // PT: --- o fluxo ---

    @Test
    void theFullFlowEndsEverySessionAndOnlyTheNewPasswordLogsIn() throws Exception {
        var email = fixtures.uniqueEmail();
        var phone = api.register(email, password).get("tokens").get("refreshToken").asString();
        var browser = api.loginRefreshToken(email, password);

        assertThat(api.requestReset(email).getStatus()).isEqualTo(202);
        var code = api.resetCodeOf(email);
        var confirmed = api.confirmReset(email, code, newPassword);

        assertThat(confirmed.getStatus()).isEqualTo(204);
        assertThat(confirmed.getContentAsString()).isEmpty();
        assertThat(api.refresh(phone).getStatus()).isEqualTo(401);
        assertThat(api.refresh(browser).getStatus()).isEqualTo(401);
        assertThat(api.login(email, password).getStatus()).isEqualTo(401);
        assertThat(api.login(email, newPassword).getStatus()).isEqualTo(200);
        assertThat(api.countSubject(email, "password was changed")).isEqualTo(1);
        assertThat(emailVerifiedAt(email)).isNotNull();
        assertThat(usedAt(email, "PASSWORD_RESET")).isNotNull();
    }

    @Test
    void theCodeWorksOnlyOnce() throws Exception {
        var email = fixtures.uniqueEmail();
        api.register(email, password);
        api.requestReset(email);
        var code = api.resetCodeOf(email);
        assertThat(api.confirmReset(email, code, newPassword).getStatus()).isEqualTo(204);

        var again = api.confirmReset(email, code, "other-" + UUID.randomUUID());

        assertThat(again.getStatus()).isEqualTo(400);
        assertThat(api.login(email, newPassword).getStatus()).isEqualTo(200);
    }

    // Sessions are not revoked by a failed confirm.
    // PT: As sessões não são revogadas por uma confirmação que falhou.
    @Test
    void aWrongCodeChangesNothingAndLeavesSessionsAlive() throws Exception {
        var email = fixtures.uniqueEmail();
        var session = api.register(email, password).get("tokens").get("refreshToken").asString();
        api.requestReset(email);
        var wrong = otherThan(api.resetCodeOf(email));

        assertThat(api.confirmReset(email, wrong, newPassword).getStatus()).isEqualTo(400);

        assertThat(api.login(email, password).getStatus()).isEqualTo(200);
        assertThat(api.refresh(session).getStatus()).isEqualTo(200);
        assertThat(api.countSubject(email, "password was changed")).isZero();
    }

    // --- no enumeration ---
    // PT: --- sem enumeração ---

    @Test
    void knownAndUnknownEmailsGetByteIdenticalResponsesOnRequestAndConfirm() throws Exception {
        var known = fixtures.uniqueEmail();
        api.register(known, password);
        var unknown = "nobody-" + UUID.randomUUID() + "@example.com";

        var requestKnown = api.requestReset(known);
        var requestUnknown = api.requestReset(unknown);
        var confirmKnown = api.confirmReset(known, otherThan(api.resetCodeOf(known)), newPassword);
        var confirmUnknown = api.confirmReset(unknown, "000000", newPassword);

        assertThat(summary(requestKnown)).isEqualTo(summary(requestUnknown));
        assertThat(requestKnown.getStatus()).isEqualTo(202);
        assertThat(requestKnown.getContentAsString()).isEmpty();
        assertThat(summary(confirmKnown)).isEqualTo(summary(confirmUnknown));
        assertThat(confirmKnown.getStatus()).isEqualTo(400);
        assertThat(api.countSubject(unknown, "")).isZero();
    }

    // Throttled (cooldown) answers like the first request: the caller learns nothing.
    // PT: Limitado (cooldown) responde como o primeiro pedido: quem chama não aprende nada.
    @Test
    void aThrottledRequestLooksLikeAnAcceptedOne() throws Exception {
        var email = fixtures.uniqueEmail();
        api.register(email, password);
        var first = api.requestReset(email);
        var codesSent = api.countSubject(email, "password reset");

        var second = api.requestReset(email);

        assertThat(summary(second)).isEqualTo(summary(first));
        assertThat(api.countSubject(email, "password reset")).isEqualTo(codesSent);
    }

    @Test
    void thePerEmailRequestLimitIsSilent() throws Exception {
        var email = "nobody-" + UUID.randomUUID() + "@example.com";

        for (int i = 0; i < limits.passwordResetPerEmail() + 3; i++) {
            assertThat(api.requestReset(email).getStatus()).isEqualTo(202);
        }
    }

    // Unknown email: 20 per hour per email, then still invalid-code (never 429, never a different body).
    // PT: Email desconhecido: 20 por hora por email, depois continua invalid-code (nunca 429, nunca outro corpo).
    @Test
    void thePerEmailConfirmLimitStaysInvalidCode() throws Exception {
        var email = "nobody-" + UUID.randomUUID() + "@example.com";
        var first = api.confirmReset(email, "000000", newPassword);

        for (int i = 0; i < limits.passwordResetConfirmPerEmail() + 2; i++) {
            assertThat(summary(api.confirmReset(email, "000000", newPassword))).isEqualTo(summary(first));
        }
    }

    // --- the GATE: failed attempts stay committed ---
    // PT: --- o PORTÃO: tentativas falhas continuam confirmadas ---

    @Test
    void aWrongCodeThroughTheRealEndpointLeavesTheAttemptAndTheFailureBudgetCounted() throws Exception {
        var email = fixtures.uniqueEmail();
        api.register(email, password);
        api.requestReset(email);
        var wrong = otherThan(api.resetCodeOf(email));

        assertThat(api.confirmReset(email, wrong, newPassword).getStatus()).isEqualTo(400);
        assertThat(api.confirmReset(email, wrong, newPassword).getStatus()).isEqualTo(400);

        var row = codeRow(email, "PASSWORD_RESET");
        assertThat(row.get("attempts")).isEqualTo(2);
        assertThat(row.get("failed_in_window")).isEqualTo(2);
        assertThat(row.get("failed_window_started_at")).isNotNull();
        assertThat(row.get("used_at")).isNull();
    }

    @Test
    void theSixthAttemptFailsEvenWithTheRightCode() throws Exception {
        var email = fixtures.uniqueEmail();
        api.register(email, password);
        api.requestReset(email);
        var code = api.resetCodeOf(email);
        var wrong = otherThan(code);
        for (int i = 0; i < 5; i++) {
            assertThat(api.confirmReset(email, wrong, newPassword).getStatus()).isEqualTo(400);
        }

        assertThat(api.confirmReset(email, code, newPassword).getStatus()).isEqualTo(400);

        assertThat(api.login(email, password).getStatus()).isEqualTo(200);
        assertThat(codeRow(email, "PASSWORD_RESET").get("used_at")).isNull();
    }

    @Test
    void aSpentFailureBudgetBlocksEvenTheRightCodeAndLogsOneSecurityEvent(CapturedOutput output) throws Exception {
        var email = fixtures.uniqueEmail();
        var userId = api.register(email, password).get("user").get("id").asString();
        api.requestReset(email);
        var code = api.resetCodeOf(email);
        // Nine failures already counted, as nine earlier wrong guesses would have left it.
        // PT: Nove falhas já contadas, como nove palpites errados anteriores teriam deixado.
        jdbc.update("""
                update account_codes set failed_in_window = 9, failed_window_started_at = now()
                where user_id = ?::uuid and purpose = 'PASSWORD_RESET'
                """, userId);

        assertThat(api.confirmReset(email, otherThan(code), newPassword).getStatus()).isEqualTo(400);
        assertThat(api.confirmReset(email, code, newPassword).getStatus()).isEqualTo(400);

        assertThat(api.login(email, password).getStatus()).isEqualTo(200);
        assertThat(codeRow(email, "PASSWORD_RESET").get("used_at")).isNull();
        assertThat(output.getAll().split("Account code failure budget exhausted userId=" + userId
                + " purpose=PASSWORD_RESET", -1)).hasSize(2);
        assertThat(output.getAll()).doesNotContain(email).doesNotContain(password);
        assertThat(standalone(output.getAll(), code)).isFalse();
    }

    // A new code request while the budget is spent is silent: 202, and nothing sent.
    // PT: Um novo pedido de código com o orçamento esgotado é silencioso: 202, e nada enviado.
    @Test
    void aSpentBudgetMakesTheRequestSilent() throws Exception {
        var email = fixtures.uniqueEmail();
        var userId = api.register(email, password).get("user").get("id").asString();
        api.requestReset(email);
        jdbc.update("""
                update account_codes set failed_in_window = 10, failed_window_started_at = now(),
                    sent_at = now() - interval '2 minutes', window_started_at = now() - interval '2 minutes'
                where user_id = ?::uuid and purpose = 'PASSWORD_RESET'
                """, userId);
        var sentBefore = api.countSubject(email, "password reset");

        assertThat(api.requestReset(email).getStatus()).isEqualTo(202);

        assertThat(api.countSubject(email, "password reset")).isEqualTo(sentBefore);
    }

    @Test
    void aVerificationCodeNeverResetsAPassword() throws Exception {
        var email = fixtures.uniqueEmail();
        api.register(email, password);
        var verification = api.verificationCodeOf(email);
        api.requestReset(email);
        assumeFalse(verification.equals(api.resetCodeOf(email)), "the two random codes collided (1 in a million)");

        assertThat(api.confirmReset(email, verification, newPassword).getStatus()).isEqualTo(400);

        assertThat(api.login(email, password).getStatus()).isEqualTo(200);
    }

    // --- concurrency ---
    // PT: --- concorrência ---

    @Test
    void twoParallelConfirmsWithTheSameCodeSucceedExactlyOnce() throws Exception {
        var email = fixtures.uniqueEmail();
        api.register(email, password);
        api.requestReset(email);
        var code = api.resetCodeOf(email);
        var passwordA = "a-" + UUID.randomUUID();
        var passwordB = "b-" + UUID.randomUUID();
        var start = new CountDownLatch(1);

        Callable<Integer> confirmA = () -> {
            await(start);
            return api.confirmReset(email, code, passwordA).getStatus();
        };
        Callable<Integer> confirmB = () -> {
            await(start);
            return api.confirmReset(email, code, passwordB).getStatus();
        };
        var a = threads.submit(confirmA);
        var b = threads.submit(confirmB);
        start.countDown();

        var statuses = new ArrayList<>(List.of(a.get(15, TimeUnit.SECONDS), b.get(15, TimeUnit.SECONDS)));
        statuses.sort(Integer::compare);
        assertThat(statuses).containsExactly(204, 400);
        var winner = statuses.indexOf(204) == 0 && a.get() == 204 ? passwordA : passwordB;
        assertThat(api.login(email, winner).getStatus()).isEqualTo(200);
        assertThat(api.login(email, password).getStatus()).isEqualTo(401);
    }

    // The family row is held by the test, so the refresh and the reset queue up behind it and both
    // are provably in flight together; whichever wins, the session (and any token the refresh issued) ends.
    // PT: A linha da família é segurada pelo teste, então o refresh e a redefinição esperam atrás dela e
    //     ficam provadamente juntos em andamento; quem ganhar, a sessão (e o token que o refresh emitiu) termina.
    @Test
    void aResetRunningWhileTheOldSessionRefreshesLeavesNoLiveSession() throws Exception {
        var email = fixtures.uniqueEmail();
        var session = api.register(email, password).get("tokens").get("refreshToken").asString();
        api.requestReset(email);
        var code = api.resetCodeOf(email);
        var family = fixtures.familyOf(session);
        var holder = holdRow("select id from refresh_token_families where id = ? for update", family, null);

        Future<MockHttpServletResponse> refresh = threads.submit(() -> api.refresh(session));
        awaitBlockedTransactions(1, jdbc);
        Future<MockHttpServletResponse> reset = threads.submit(() -> api.confirmReset(email, code, newPassword));
        awaitBlockedTransactions(2, jdbc);
        holder.release();

        var refreshed = refresh.get(15, TimeUnit.SECONDS);
        assertThat(reset.get(15, TimeUnit.SECONDS).getStatus()).isEqualTo(204);
        holder.join();
        assertThat(fixtures.revokedAt(family)).isNotNull();
        assertThat(api.refresh(session).getStatus()).isEqualTo(401);
        if (refreshed.getStatus() == 200) {
            var issued = JSON.readTree(refreshed.getContentAsString()).get("refreshToken").asString();
            assertThat(api.refresh(issued).getStatus()).isEqualTo(401);
        }
    }

    // Owner decision Q5 (race closed): the user row is held while login has already verified the old
    // password; the hash changes and commits; the login must then fail and start no session.
    // PT: Decisão Q5 (corrida fechada): a linha do usuário é segurada enquanto o login já verificou a
    //     senha antiga; o hash muda e faz commit; o login precisa então falhar e não iniciar sessão.
    @Test
    void aLoginThatVerifiedTheOldPasswordCannotStartASessionAfterTheHashChanged() throws Exception {
        var email = fixtures.uniqueEmail();
        var userId = api.register(email, password).get("user").get("id").asString();
        var holder = holdRow("select id from users where id = ?::uuid for update", userId,
                "update users set password_hash = '" + TestPasswordHashes.BCRYPT + "' where id = ?::uuid");

        Future<MockHttpServletResponse> login = threads.submit(() -> api.login(email, password));
        awaitBlockedTransactions(1, jdbc);
        holder.release();

        assertThat(login.get(15, TimeUnit.SECONDS).getStatus()).isEqualTo(401);
        holder.join();
        assertThat(jdbc.queryForObject("""
                select count(*) from refresh_token_families where user_id = ?::uuid
                """, Long.class, userId)).isEqualTo(1);
    }

    // --- per-IP limit ---
    // PT: --- limite por IP ---

    @Test
    void thePerIpLimitAnswers429WithRetryAfterOnBothEndpoints() throws Exception {
        var ip = newIp();
        for (int i = 0; i < limits.passwordResetPerIp(); i++) {
            assertThat(api.requestReset("nobody-" + UUID.randomUUID() + "@example.com", ip).getStatus()).isEqualTo(202);
        }
        var blocked = api.requestReset("nobody-" + UUID.randomUUID() + "@example.com", ip);

        assertThat(blocked.getStatus()).isEqualTo(429);
        assertThat(blocked.getHeader(HttpHeaders.RETRY_AFTER)).matches("^[1-9][0-9]*$");
        assertThat(blocked.getContentAsString()).contains("urn:snapledger:problem:too-many-requests");

        var confirmIp = newIp();
        for (int i = 0; i < limits.passwordResetConfirmPerIp(); i++) {
            assertThat(api.confirmReset("nobody-" + UUID.randomUUID() + "@example.com", "000000", newPassword,
                    confirmIp).getStatus()).isEqualTo(400);
        }
        assertThat(api.confirmReset("nobody-" + UUID.randomUUID() + "@example.com", "000000", newPassword,
                confirmIp).getStatus()).isEqualTo(429);
    }

    // --- logs ---
    // PT: --- logs ---

    @Test
    void noCodeEmailOrPasswordReachesTheLogs(CapturedOutput output) throws Exception {
        var email = fixtures.uniqueEmail();
        api.register(email, password);
        api.requestReset(email);
        var code = api.resetCodeOf(email);
        var verification = api.verificationCodeOf(email);
        api.confirmReset(email, otherThan(code), newPassword);
        api.confirmReset(email, code, newPassword);
        api.confirmReset("nobody-" + UUID.randomUUID() + "@example.com", code, newPassword);

        var logs = output.getAll();
        assertThat(logs).doesNotContain(email).doesNotContain(password).doesNotContain(newPassword);
        assertThat(standalone(logs, code)).isFalse();
        assertThat(standalone(logs, verification)).isFalse();
    }

    // ---

    // A 6-digit string that is not part of a longer token (a UUID, a timestamp, a pid).
    // PT: Uma string de 6 dígitos que não faz parte de um token maior (um UUID, um timestamp, um pid).
    private static boolean standalone(String logs, String code) {
        return Pattern.compile("(?<![0-9A-Za-z])" + code + "(?![0-9A-Za-z])").matcher(logs).find();
    }

    private static String otherThan(String code) {
        return code.equals("000000") ? "000001" : "000000";
    }

    private static Map<String, Object> summary(MockHttpServletResponse response) throws Exception {
        var headers = new TreeMap<String, List<String>>();
        response.getHeaderNames().forEach(name -> headers.put(name, response.getHeaders(name)));
        return Map.of("status", response.getStatus(), "headers", headers, "body", response.getContentAsString());
    }

    private Map<String, Object> codeRow(String email, String purpose) {
        return jdbc.queryForMap("""
                select c.* from account_codes c join users u on u.id = c.user_id
                where u.email = ? and c.purpose = ?
                """, email, purpose);
    }

    private Object usedAt(String email, String purpose) {
        return codeRow(email, purpose).get("used_at");
    }

    private Object emailVerifiedAt(String email) {
        return jdbc.queryForObject("select email_verified_at from users where email = ?", Object.class, email);
    }

    /** A transaction that holds a row lock until {@link RowHolder#release()}, then optionally updates and commits. */
    private RowHolder holdRow(String lockSql, Object id, String thenUpdate) throws Exception {
        var holder = new RowHolder();
        var locked = new CountDownLatch(1);
        holder.done = threads.submit(() -> {
            new TransactionTemplate(transactionManager).executeWithoutResult(status -> {
                jdbc.queryForList(lockSql, id);
                locked.countDown();
                await(holder.go);
                if (thenUpdate != null) {
                    jdbc.update(thenUpdate, id);
                }
            });
            return null;
        });
        await(locked);
        return holder;
    }

    private static final class RowHolder {

        final CountDownLatch go = new CountDownLatch(1);
        Future<?> done;

        void release() {
            go.countDown();
        }

        void join() throws Exception {
            done.get(15, TimeUnit.SECONDS);
        }
    }
}
