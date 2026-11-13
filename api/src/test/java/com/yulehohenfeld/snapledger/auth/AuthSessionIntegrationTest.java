package com.yulehohenfeld.snapledger.auth;

import static com.yulehohenfeld.snapledger.support.LockWaits.await;
import static com.yulehohenfeld.snapledger.support.TestTokenHashes.hashOf;
import static org.assertj.core.api.Assertions.assertThat;

import java.time.Duration;
import java.time.Instant;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.Callable;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;

import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.system.CapturedOutput;
import org.springframework.boot.test.system.OutputCaptureExtension;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.context.annotation.Import;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.mock.web.MockHttpServletResponse;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.request.MockMvcRequestBuilders;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;

import tools.jackson.databind.JsonNode;
import tools.jackson.databind.json.JsonMapper;

import com.yulehohenfeld.snapledger.support.RefreshTokenFixtures;
import com.yulehohenfeld.snapledger.support.TestJwtSecret;
import com.yulehohenfeld.snapledger.support.TestTokens;
import com.yulehohenfeld.snapledger.support.TestcontainersConfiguration;

/**
 * Refresh and logout end to end on a real PostgreSQL: rotation, reuse, logout, the separate auth
 * chain and what reaches the logs. MockMvc, never a port; no spies, so the context is shared with
 * RefreshTokenServiceIntegrationTest.
 *
 * <p>PT: Refresh e logout de ponta a ponta num PostgreSQL real: rotação, reuso, logout, a cadeia de
 * auth separada e o que chega aos logs. MockMvc, nunca uma porta; sem spies, então o contexto é
 * compartilhado com o RefreshTokenServiceIntegrationTest.
 * Notes: docs/code-notes/auth.md#refresh
 */
@ExtendWith(OutputCaptureExtension.class)
@SpringBootTest
@AutoConfigureMockMvc
@Import({TestcontainersConfiguration.class, TestJwtSecret.class})
class AuthSessionIntegrationTest {

    static final String REGISTER = "/api/v1/auth/register";
    static final String LOGIN = "/api/v1/auth/login";
    static final String REFRESH = "/api/v1/auth/refresh";
    static final String LOGOUT = "/api/v1/auth/logout";
    static final String ME = "/api/v1/users/me";
    static final JsonMapper JSON = JsonMapper.builder().build();

    @Autowired
    MockMvc mvc;

    @Autowired
    JdbcTemplate jdbc;

    @Autowired
    RefreshTokenFamilyRepository families;

    @Autowired
    PlatformTransactionManager transactionManager;

    // Random per test instance: no literal password in tests.
    // PT: Aleatória por instância de teste: nenhuma senha literal nos testes.
    private final String password = "pw-" + UUID.randomUUID();
    private RefreshTokenFixtures fixtures;
    private ExecutorService threads;

    @BeforeEach
    void setUp() {
        fixtures = new RefreshTokenFixtures(jdbc);
        threads = Executors.newFixedThreadPool(2);
    }

    @AfterEach
    void cleanUp() {
        fixtures.cleanUp(threads);
    }

    @Test
    void refreshReturnsANewPairAndTheOldRefreshTokenThenFails() throws Exception {
        var session = register();
        var old = session.get("refreshToken").asString();

        var refreshed = refresh(old);

        assertThat(refreshed.getStatus()).isEqualTo(200);
        assertThat(refreshed.getHeader(HttpHeaders.CACHE_CONTROL)).isEqualTo("no-store");
        var tokens = JSON.readTree(refreshed.getContentAsString());
        assertThat(tokens.propertyNames())
                .containsExactlyInAnyOrder("accessToken", "tokenType", "expiresIn", "refreshToken", "refreshExpiresIn");
        assertThat(tokens.get("refreshToken").asString()).isNotEqualTo(old).matches("^[A-Za-z0-9_-]{43}$");
        assertThat(tokens.get("expiresIn").asLong()).isEqualTo(900);
        assertThat(tokens.get("refreshExpiresIn").asLong()).isEqualTo(2_592_000);
        assertThat(fixtures.familyOf(tokens.get("refreshToken").asString())).isEqualTo(fixtures.familyOf(old));
        assertThat(isInvalidRefreshToken(refresh(old))).isTrue();
    }

    // The access token from refresh is accepted by the strict decoder (aud, iss, sub of the owner).
    // PT: O token de acesso do refresh é aceito pelo decoder estrito (aud, iss, sub do dono).
    @Test
    void theNewAccessTokenOpensUsersMeOfTheSameUser() throws Exception {
        var email = fixtures.uniqueEmail();
        var session = register(email);

        var tokens = JSON.readTree(refresh(session.get("refreshToken").asString()).getContentAsString());
        var me = get(ME, TestTokens.bearer(tokens.get("accessToken").asString()));

        assertThat(me.getStatus()).isEqualTo(200);
        assertThat(JSON.readTree(me.getContentAsString()).get("email").asString()).isEqualTo(email);
    }

    // Reuse over HTTP kills the session, newest token included; logging in again still works.
    // PT: Reuso por HTTP mata a sessão, inclusive o token mais novo; entrar de novo ainda funciona.
    @Test
    void reusingARefreshTokenRevokesTheSessionAndTheUserCanLogInAgain() throws Exception {
        var email = fixtures.uniqueEmail();
        var first = register(email).get("refreshToken").asString();
        var second = JSON.readTree(refresh(first).getContentAsString()).get("refreshToken").asString();

        assertThat(isInvalidRefreshToken(refresh(first))).isTrue();
        assertThat(isInvalidRefreshToken(refresh(second))).isTrue();
        assertThat(fixtures.revokedAt(fixtures.familyOf(first))).isNotNull();

        var login = post(LOGIN, JSON.writeValueAsString(Map.of("email", email, "password", password)));
        assertThat(login.getStatus()).isEqualTo(200);
        var fresh = JSON.readTree(login.getContentAsString()).get("tokens").get("refreshToken").asString();
        assertThat(refresh(fresh).getStatus()).isEqualTo(200);
    }

    @Test
    void logoutIs204AndTheTokenCannotRefreshAnymore() throws Exception {
        var token = register().get("refreshToken").asString();

        var logout = logout(token);

        assertThat(logout.getStatus()).isEqualTo(204);
        assertThat(logout.getContentAsString()).isEmpty();
        assertThat(isInvalidRefreshToken(refresh(token))).isTrue();
        assertThat(logout(token).getStatus()).isEqualTo(204);
    }

    @Test
    void logoutOfAnUnknownTokenIs204() throws Exception {
        assertThat(logout("unknown-" + UUID.randomUUID()).getStatus()).isEqualTo(204);
    }

    // Owner decision Q2: an expired token the server knows still ends its session.
    // PT: Decisão Q2: um token vencido que o servidor conhece ainda encerra a sessão dele.
    @Test
    void logoutWithAnExpiredTokenIs204AndEndsTheSession() throws Exception {
        var live = register().get("refreshToken").asString();
        var expired = fixtures.insertExpiredToken(fixtures.familyOf(live));

        assertThat(logout(expired).getStatus()).isEqualTo(204);

        assertThat(fixtures.revokedAt(fixtures.familyOf(live))).isNotNull();
        assertThat(isInvalidRefreshToken(refresh(live))).isTrue();
    }

    @Test
    void logoutOfOneSessionLeavesTheOtherSessionAlive() throws Exception {
        var email = fixtures.uniqueEmail();
        var phone = register(email).get("refreshToken").asString();
        var browser = JSON.readTree(post(LOGIN, JSON.writeValueAsString(Map.of("email", email, "password", password)))
                .getContentAsString()).get("tokens").get("refreshToken").asString();

        assertThat(logout(phone).getStatus()).isEqualTo(204);

        assertThat(refresh(browser).getStatus()).isEqualTo(200);
    }

    // Unknown, expired, revoked and reused: byte-for-byte the same 401 (contract).
    // PT: Desconhecido, vencido, revogado e reusado: exatamente o mesmo 401 (contrato).
    @Test
    void theFourFailureCausesGiveIdenticalBodies() throws Exception {
        var unknown = refresh("unknown-" + UUID.randomUUID());

        var expiredSession = register().get("refreshToken").asString();
        var expired = refresh(fixtures.insertExpiredToken(fixtures.familyOf(expiredSession)));

        var revokedToken = register().get("refreshToken").asString();
        logout(revokedToken);
        var revoked = refresh(revokedToken);

        var reusedToken = register().get("refreshToken").asString();
        refresh(reusedToken);
        var reused = refresh(reusedToken);

        assertThat(List.of(unknown, expired, revoked, reused)).allSatisfy(response -> {
            assertThat(response.getStatus()).isEqualTo(401);
            assertThat(response.getHeader(HttpHeaders.WWW_AUTHENTICATE)).isNull();
            assertThat(response.getContentAsString()).isEqualTo(unknown.getContentAsString());
        });
        assertThat(isInvalidRefreshToken(unknown)).isTrue();
    }

    // ADR 0005: chain 1 ignores Authorization, while chain 2 (/users/me) still rejects the same header.
    // PT: ADR 0005: a cadeia 1 ignora o Authorization, enquanto a cadeia 2 (/users/me) ainda rejeita o
    //     mesmo header.
    @ParameterizedTest
    @ValueSource(strings = {"garbage", "expired"})
    void refreshAndLogoutIgnoreABadAuthorizationHeader(String kind) throws Exception {
        var header = kind.equals("garbage")
                ? "Bearer not-a-jwt"
                : TestTokens.bearer(TestTokens.valid(Instant.now().minus(Duration.ofDays(1))));
        var token = register().get("refreshToken").asString();

        var refreshed = mvc.perform(MockMvcRequestBuilders.post(REFRESH).contentType(MediaType.APPLICATION_JSON)
                        .content(refreshBody(token)).header(HttpHeaders.AUTHORIZATION, header))
                .andReturn().getResponse();
        var next = JSON.readTree(refreshed.getContentAsString()).get("refreshToken").asString();
        var logout = mvc.perform(MockMvcRequestBuilders.post(LOGOUT).contentType(MediaType.APPLICATION_JSON)
                        .content(refreshBody(next)).header(HttpHeaders.AUTHORIZATION, header))
                .andReturn().getResponse();

        assertThat(refreshed.getStatus()).isEqualTo(200);
        assertThat(logout.getStatus()).isEqualTo(204);
        assertThat(get(ME, header).getStatus()).isEqualTo(401);
    }

    /**
     * A session lock held past lock_timeout: refresh and logout answer a masked 500, never 401 (which
     * would wipe a healthy session), and the token still works afterwards. The one exception to
     * "logout always 204" (contract edge cases).
     *
     * <p>PT: Um lock de sessão segurado além do lock_timeout: refresh e logout respondem um 500
     * mascarado, nunca 401 (que apagaria uma sessão saudável), e o token ainda funciona depois. A
     * única exceção ao "logout sempre 204" (casos de borda do contrato).
     * Notes: docs/code-notes/security.md#lock_timeout
     */
    @Test
    void aLockTimeoutIsAMasked500AndTheTokenStillWorksAfterwards() throws Exception {
        var token = register().get("refreshToken").asString();
        var family = fixtures.familyOf(token);

        // One hold per request: each lasts about lock_timeout (3 s), well under LockWaits' 10 s deadline.
        // PT: Um lock por requisição: cada um dura cerca de lock_timeout (3 s), bem abaixo do prazo de 10 s
        //     do LockWaits.
        var refreshed = whileFamilyIsLocked(family, () -> refresh(token));
        var logout = whileFamilyIsLocked(family, () -> logout(token));

        assertThat(List.of(refreshed, logout)).allSatisfy(response -> {
            assertThat(response.getStatus()).isEqualTo(500);
            assertThat(response.getHeader(HttpHeaders.WWW_AUTHENTICATE)).isNull();
            var body = JSON.readTree(response.getContentAsString());
            assertThat(body.get("type").asString()).isEqualTo("urn:snapledger:problem:internal-error");
            assertThat(body.get("errorId").asString()).isNotBlank();
            assertThat(response.getContentAsString()).doesNotContain(token).doesNotContain(hashOf(token));
        });
        assertThat(fixtures.revokedAt(family)).isNull();
        assertThat(refresh(token).getStatus()).isEqualTo(200);
    }

    // A client without single-flight: exactly one 200, one 401, and the session is revoked (ADR 0002).
    // PT: Um cliente sem single-flight: exatamente um 200, um 401, e a sessão é revogada (ADR 0002).
    @Test
    void twoConcurrentRefreshesWithTheSameTokenGiveOne200AndOne401() throws Exception {
        var token = register().get("refreshToken").asString();
        var start = new CountDownLatch(1);
        Callable<Integer> refresh = () -> {
            await(start);
            return refresh(token).getStatus();
        };
        var first = threads.submit(refresh);
        var second = threads.submit(refresh);
        start.countDown();

        var statuses = List.of(first.get(20, TimeUnit.SECONDS), second.get(20, TimeUnit.SECONDS));

        assertThat(statuses).containsExactlyInAnyOrder(200, 401);
        assertThat(fixtures.revokedAt(fixtures.familyOf(token))).isNotNull();
    }

    // api/CLAUDE.md security rule 8: no token or hash in any log; the reuse WARN carries only the family id.
    // PT: Regra de segurança 8 do api/CLAUDE.md: nenhum token ou hash em log nenhum; o WARN de reuso leva
    //     só o id da família.
    @Test
    void noTokenOrHashReachesTheLogs(CapturedOutput output) throws Exception {
        var email = fixtures.uniqueEmail();
        var session = register(email);
        var first = session.get("refreshToken").asString();
        var refreshed = JSON.readTree(refresh(first).getContentAsString());
        var second = refreshed.get("refreshToken").asString();
        var unknown = "unknown-" + UUID.randomUUID();
        refresh(first);
        refresh(unknown);
        logout(second);
        var family = fixtures.familyOf(first);

        var secrets = List.of(first, second, unknown, hashOf(first), hashOf(second), hashOf(unknown),
                session.get("accessToken").asString(), refreshed.get("accessToken").asString());
        assertThat(secrets).allSatisfy(secret -> assertThat(output.getAll()).doesNotContain(secret));
        var warnings = output.getAll().lines().filter(line -> line.contains("reuse detected")).toList();
        assertThat(warnings).singleElement().satisfies(line -> assertThat(line)
                .contains("WARN")
                .endsWith("Refresh token reuse detected; family revoked familyId=" + family)
                .doesNotContain(email));
    }

    private JsonNode register() throws Exception {
        return register(fixtures.uniqueEmail());
    }

    private JsonNode register(String email) throws Exception {
        var response = post(REGISTER, JSON.writeValueAsString(Map.of("name", "Ana Souza", "email", email,
                "password", password)));
        assertThat(response.getStatus()).isEqualTo(201);
        return JSON.readTree(response.getContentAsString()).get("tokens");
    }

    private MockHttpServletResponse refresh(String refreshToken) throws Exception {
        return post(REFRESH, refreshBody(refreshToken));
    }

    private MockHttpServletResponse logout(String refreshToken) throws Exception {
        return post(LOGOUT, refreshBody(refreshToken));
    }

    private MockHttpServletResponse post(String path, String json) throws Exception {
        return mvc.perform(MockMvcRequestBuilders.post(path).contentType(MediaType.APPLICATION_JSON).content(json))
                .andReturn().getResponse();
    }

    private MockHttpServletResponse get(String path, String authorization) throws Exception {
        return mvc.perform(MockMvcRequestBuilders.get(path).header(HttpHeaders.AUTHORIZATION, authorization))
                .andReturn().getResponse();
    }

    private static boolean isInvalidRefreshToken(MockHttpServletResponse response) throws Exception {
        return response.getStatus() == 401
                && JSON.readTree(response.getContentAsString()).get("type").asString()
                        .equals("urn:snapledger:problem:invalid-refresh-token");
    }

    // Holds the family lock in another transaction while one request runs, then releases it.
    // PT: Segura o lock da família em outra transação enquanto uma requisição roda, depois o solta.
    private MockHttpServletResponse whileFamilyIsLocked(UUID family, Callable<MockHttpServletResponse> request)
            throws Exception {
        var tx = new TransactionTemplate(transactionManager);
        var locked = new CountDownLatch(1);
        var release = new CountDownLatch(1);
        try {
            var holder = threads.submit(() -> tx.execute(status -> {
                families.lockActive(family).orElseThrow();
                locked.countDown();
                await(release);
                return null;
            }));
            await(locked);
            var response = request.call();
            release.countDown();
            holder.get(10, TimeUnit.SECONDS);
            return response;
        } finally {
            release.countDown();
        }
    }

    private static String refreshBody(String refreshToken) {
        return JSON.writeValueAsString(Map.of("refreshToken", refreshToken));
    }
}
