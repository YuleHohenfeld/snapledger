package com.yulehohenfeld.snapledger.auth.service;

import static com.yulehohenfeld.snapledger.support.LockWaits.await;
import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.doAnswer;
import static org.mockito.Mockito.doThrow;

import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.Callable;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;

import jakarta.persistence.EntityManager;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.context.annotation.Import;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.mock.web.MockHttpServletResponse;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.test.context.bean.override.mockito.MockitoSpyBean;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.request.MockMvcRequestBuilders;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionSynchronizationManager;
import org.springframework.transaction.support.TransactionTemplate;

import tools.jackson.databind.json.JsonMapper;

import com.yulehohenfeld.snapledger.support.LockWaits;
import com.yulehohenfeld.snapledger.support.TestJwtSecret;
import com.yulehohenfeld.snapledger.support.TestPasswordHashes;
import com.yulehohenfeld.snapledger.support.TestcontainersConfiguration;

/**
 * Register, login and {@code /users/me} end to end on a real PostgreSQL; MockMvc, never a port.
 *
 * <p>PT: Cadastro, login e {@code /users/me} de ponta a ponta num PostgreSQL real; MockMvc, nunca
 * uma porta.
 * Notes: docs/code-notes/security.md#containererrordispatchintegrationtest
 */
@SpringBootTest
@AutoConfigureMockMvc
@Import({TestcontainersConfiguration.class, TestJwtSecret.class})
class AuthIntegrationTest {

    static final String REGISTER = "/api/v1/auth/register";
    static final String LOGIN = "/api/v1/auth/login";
    static final String ME = "/api/v1/users/me";
    static final JsonMapper JSON = JsonMapper.builder().build();

    @Autowired
    MockMvc mvc;

    @Autowired
    JdbcTemplate jdbc;

    @Autowired
    EntityManager entityManager;

    @Autowired
    PlatformTransactionManager transactionManager;

    @MockitoSpyBean
    RefreshTokenService refreshTokens;

    @MockitoSpyBean
    PasswordEncoder passwordEncoder;

    // Random per test instance: no literal password in tests.
    // PT: Aleatória por instância de teste: nenhuma senha literal nos testes.
    private final String password = "pw-" + UUID.randomUUID();

    @Test
    void registerStartsASessionWhoseAccessTokenOpensUsersMe() throws Exception {
        var email = uniqueEmail();

        var registered = post(REGISTER, registerBody(email, password));

        assertThat(registered.getStatus()).isEqualTo(201);
        var body = JSON.readTree(registered.getContentAsString());
        var me = get(ME, body.get("tokens").get("accessToken").asString());

        assertThat(me.getStatus()).isEqualTo(200);
        assertThat(JSON.readTree(me.getContentAsString())).isEqualTo(body.get("user"));
        assertThat(body.get("user").get("email").asString()).isEqualTo(email);
    }

    // ADR 0009: bcrypt runs before register's transaction opens, so no pool connection waits on it.
    // PT: ADR 0009: o bcrypt roda antes de a transação do cadastro abrir, então nenhuma conexão do
    //     pool espera por ele.
    @Test
    void registerHashesThePasswordWithNoTransactionOpen() throws Exception {
        var activeDuringHash = Collections.synchronizedList(new ArrayList<Boolean>());
        doAnswer(invocation -> {
            activeDuringHash.add(TransactionSynchronizationManager.isActualTransactionActive());
            return invocation.callRealMethod();
        }).when(passwordEncoder).encode(eq(password));

        assertThat(post(REGISTER, registerBody(uniqueEmail(), password)).getStatus()).isEqualTo(201);

        assertThat(activeDuringHash).containsExactly(false);
    }

    @Test
    void registerStoresOnlyTheHashOfTheRefreshTokenAndABcryptPasswordHash() throws Exception {
        var email = uniqueEmail();

        var tokens = JSON.readTree(post(REGISTER, registerBody(email, password)).getContentAsString()).get("tokens");
        var raw = tokens.get("refreshToken").asString();

        assertThat(raw).matches("^[A-Za-z0-9_-]{43}$");
        assertThat(jdbc.queryForObject("""
                select count(*) from refresh_tokens t
                join refresh_token_families f on f.id = t.family_id
                join users u on u.id = f.user_id
                where u.email = ? and t.token_hash = ?
                """, Integer.class, email, RefreshTokenService.sha256(raw))).isEqualTo(1);
        assertThat(jdbc.queryForObject("select count(*) from refresh_tokens where token_hash = ?",
                Integer.class, raw)).isZero();
        assertThat(jdbc.queryForObject("select password_hash from users where email = ?", String.class, email))
                .startsWith("$2a$10$")
                .doesNotContain(password);
    }

    @Test
    void duplicateEmailInAnyCaseIs409AndCreatesNothing() throws Exception {
        var email = uniqueEmail();
        assertThat(post(REGISTER, registerBody(email, password)).getStatus()).isEqualTo(201);

        var duplicate = post(REGISTER, registerBody(email.toUpperCase(Locale.ROOT), "other-" + password));

        assertThat(duplicate.getStatus()).isEqualTo(409);
        assertThat(type(duplicate)).isEqualTo("urn:snapledger:problem:email-already-registered");
        assertThat(duplicate.getContentAsString()).doesNotContain(email).doesNotContain(email.toUpperCase(Locale.ROOT));
        assertThat(countUsers(email)).isEqualTo(1);
        assertThat(countFamilies(email)).isEqualTo(1);
    }

    @Test
    void concurrentRegistersOfTheSameEmailGiveExactlyOne201AndOne409() throws Exception {
        var email = uniqueEmail();
        var start = new CountDownLatch(1);
        var threads = Executors.newFixedThreadPool(2);
        try {
            Callable<Integer> register = () -> {
                await(start);
                return post(REGISTER, registerBody(email, password)).getStatus();
            };
            var first = threads.submit(register);
            var second = threads.submit(register);
            start.countDown();

            var statuses = List.of(first.get(20, TimeUnit.SECONDS), second.get(20, TimeUnit.SECONDS));

            assertThat(statuses).containsExactlyInAnyOrder(201, 409);
            assertThat(countUsers(email)).isEqualTo(1);
            assertThat(countFamilies(email)).isEqualTo(1);
        } finally {
            threads.shutdownNow();
        }
    }

    @Test
    void loginWithAnyCaseOfTheEmailStartsAnotherSession() throws Exception {
        var email = uniqueEmail();
        post(REGISTER, registerBody(email, password));

        var login = post(LOGIN, loginBody(email.toUpperCase(Locale.ROOT), password));

        assertThat(login.getStatus()).isEqualTo(200);
        var body = JSON.readTree(login.getContentAsString());
        assertThat(body.get("user").get("email").asString()).isEqualTo(email);
        assertThat(get(ME, body.get("tokens").get("accessToken").asString()).getStatus()).isEqualTo(200);
        assertThat(countFamilies(email)).isEqualTo(2);
    }

    // No enumeration with the real service and database: byte-for-byte the same body (contract).
    // PT: Sem enumeração com o Service e o banco reais: exatamente o mesmo corpo (contrato).
    @Test
    void wrongPasswordAndUnknownEmailGiveIdenticalBodiesAndStartNoSession() throws Exception {
        var email = uniqueEmail();
        post(REGISTER, registerBody(email, password));

        var wrongPassword = post(LOGIN, loginBody(email, "wrong-" + password));
        var unknownEmail = post(LOGIN, loginBody(uniqueEmail(), password));

        assertThat(wrongPassword.getStatus()).isEqualTo(401);
        assertThat(unknownEmail.getStatus()).isEqualTo(401);
        assertThat(wrongPassword.getContentAsString()).isEqualTo(unknownEmail.getContentAsString());
        assertThat(countFamilies(email)).isEqualTo(1);
    }

    @ParameterizedTest
    @ValueSource(strings = {"josé@example.com", " ana@example.com", "ana@example.com\t"})
    void emailWithAccentOrWhitespaceIs400AndStoresNothing(String email) throws Exception {
        assertThat(post(REGISTER, registerBody(email, password)).getStatus()).isEqualTo(400);
        assertThat(countUsers(email.strip())).isZero();
    }

    // Contract: a register that fails after the user insert leaves no account behind.
    // PT: Contrato: um cadastro que falha depois do insert do usuário não deixa conta para trás.
    @Test
    void registerThatFailsAfterTheUserInsertLeavesNoUser() throws Exception {
        var email = uniqueEmail();
        doThrow(new IllegalStateException("forced failure")).when(refreshTokens).startFamily(any());

        var response = post(REGISTER, registerBody(email, password));

        assertThat(response.getStatus()).isEqualTo(500);
        assertThat(JSON.readTree(response.getContentAsString()).get("errorId").asString()).isNotBlank();
        assertThat(countUsers(email)).isZero();
    }

    @Test
    void tokenOfAUserThatNoLongerExistsIs401Unauthorized() throws Exception {
        var email = uniqueEmail();
        var access = JSON.readTree(post(REGISTER, registerBody(email, password)).getContentAsString())
                .get("tokens").get("accessToken").asString();
        jdbc.update("delete from users where email = ?", email);

        var me = get(ME, access);

        assertThat(me.getStatus()).isEqualTo(401);
        assertThat(me.getHeader(HttpHeaders.WWW_AUTHENTICATE)).isEqualTo("Bearer");
        assertThat(type(me)).isEqualTo("urn:snapledger:problem:unauthorized");
    }

    /**
     * Blocked behind an uncommitted insert of the same email past lock_timeout: a masked 500, never 409 or 401.
     *
     * <p>PT: Preso atrás de um insert sem commit do mesmo email além do lock_timeout: um 500
     * mascarado, nunca 409 ou 401.
     * Notes: docs/code-notes/security.md#lock_timeout
     */
    @Test
    void registerBlockedPastTheLockTimeoutIsAMasked500() throws Exception {
        var email = uniqueEmail();
        var tx = new TransactionTemplate(transactionManager);
        var inserted = new CountDownLatch(1);
        var release = new CountDownLatch(1);
        var threads = Executors.newFixedThreadPool(2);
        try {
            var holder = threads.submit(() -> tx.executeWithoutResult(status -> {
                jdbc.update("""
                        insert into users (id, name, email, password_hash, currency, created_at)
                        values (?, 'Holder', ?, ?, 'BRL', now())
                        """, UUID.randomUUID(), email, TestPasswordHashes.BCRYPT);
                inserted.countDown();
                await(release);
                status.setRollbackOnly();
            }));
            assertThat(inserted.await(10, TimeUnit.SECONDS)).isTrue();

            var register = threads.submit(() -> post(REGISTER, registerBody(email, password)));
            LockWaits.awaitOneBlockedTransaction(tx, entityManager); // the register really waits on the lock
            var response = register.get(LockWaits.LOCK_TIMEOUT.toSeconds() + 10, TimeUnit.SECONDS);
            release.countDown();
            holder.get(10, TimeUnit.SECONDS);

            assertThat(response.getStatus()).isEqualTo(500);
            assertThat(response.getHeader(HttpHeaders.WWW_AUTHENTICATE)).isNull();
            var body = JSON.readTree(response.getContentAsString());
            assertThat(body.get("type").asString()).isEqualTo("urn:snapledger:problem:internal-error");
            assertThat(body.get("detail").asString()).isEqualTo("An unexpected error occurred.");
            assertThat(body.get("errorId").asString()).isNotBlank();
            assertThat(response.getContentAsString()).doesNotContain(email);
            assertThat(countUsers(email)).isZero();
        } finally {
            release.countDown();
            threads.shutdownNow();
        }
    }

    private int countUsers(String email) {
        return jdbc.queryForObject("select count(*) from users where email = ?", Integer.class, email);
    }

    private int countFamilies(String email) {
        return jdbc.queryForObject("""
                select count(*) from refresh_token_families f join users u on u.id = f.user_id where u.email = ?
                """, Integer.class, email);
    }

    private MockHttpServletResponse post(String path, String json) throws Exception {
        return mvc.perform(MockMvcRequestBuilders.post(path).contentType(MediaType.APPLICATION_JSON).content(json))
                .andReturn().getResponse();
    }

    private MockHttpServletResponse get(String path, String accessToken) throws Exception {
        return mvc.perform(MockMvcRequestBuilders.get(path).header(HttpHeaders.AUTHORIZATION, "Bearer " + accessToken))
                .andReturn().getResponse();
    }

    private static String type(MockHttpServletResponse response) throws Exception {
        return JSON.readTree(response.getContentAsString()).get("type").asString();
    }

    private static String registerBody(String email, String password) {
        return JSON.writeValueAsString(Map.of("name", "Ana Souza", "email", email, "password", password));
    }

    private static String loginBody(String email, String password) {
        return JSON.writeValueAsString(Map.of("email", email, "password", password));
    }

    private static String uniqueEmail() {
        return "user-" + UUID.randomUUID() + "@example.com";
    }
}
