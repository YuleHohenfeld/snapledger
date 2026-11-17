package com.yulehohenfeld.snapledger.support;

import java.util.Map;
import java.util.concurrent.ThreadLocalRandom;
import java.util.regex.Pattern;

import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.mock.web.MockHttpServletResponse;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.request.MockHttpServletRequestBuilder;
import org.springframework.test.web.servlet.request.MockMvcRequestBuilders;

import tools.jackson.databind.JsonNode;
import tools.jackson.databind.json.JsonMapper;

/**
 * The account endpoints as the app calls them, for integration tests: every call comes from its own
 * client address unless the test passes one, so the in-memory per-IP limits of one test never leak
 * into another.
 *
 * <p>PT: Os endpoints de conta como o app os chama, para testes de integração: cada chamada vem de um
 * endereço de cliente próprio, a menos que o teste passe um, então os limites por IP em memória de um
 * teste nunca vazam para outro.
 */
public final class AccountApi {

    public static final String REGISTER = "/api/v1/auth/register";
    public static final String LOGIN = "/api/v1/auth/login";
    public static final String REFRESH = "/api/v1/auth/refresh";
    public static final String RESET = "/api/v1/auth/password-reset";
    public static final String RESET_VERIFY = "/api/v1/auth/password-reset/verify";
    public static final String RESET_CONFIRM = "/api/v1/auth/password-reset/confirm";
    public static final String ME = "/api/v1/users/me";
    public static final String VERIFY = ME + "/email-verification";
    public static final String VERIFY_CONFIRM = VERIFY + "/confirm";

    private static final JsonMapper JSON = JsonMapper.builder().build();
    private static final Pattern SIX_DIGITS = Pattern.compile("\\b(\\d{6})\\b");

    private final MockMvc mvc;
    private final FakeEmailSender mail;

    public AccountApi(MockMvc mvc, FakeEmailSender mail) {
        this.mvc = mvc;
        this.mail = mail;
    }

    public static String newIp() {
        var random = ThreadLocalRandom.current();
        return "10." + random.nextInt(256) + "." + random.nextInt(256) + "." + random.nextInt(1, 255);
    }

    /** Registers and returns the {@code AuthResponse} JSON. PT: Cadastra e devolve o JSON do {@code AuthResponse}. */
    public JsonNode register(String email, String password) throws Exception {
        var response = post(REGISTER, Map.of("name", "Ana Souza", "email", email, "password", password), null);
        return JSON.readTree(response.getContentAsString());
    }

    public MockHttpServletResponse login(String email, String password) throws Exception {
        return post(LOGIN, Map.of("email", email, "password", password), null);
    }

    public String loginRefreshToken(String email, String password) throws Exception {
        return JSON.readTree(login(email, password).getContentAsString()).get("tokens").get("refreshToken").asString();
    }

    public MockHttpServletResponse refresh(String refreshToken) throws Exception {
        return post(REFRESH, Map.of("refreshToken", refreshToken), null);
    }

    public MockHttpServletResponse requestReset(String email) throws Exception {
        return requestReset(email, newIp());
    }

    public MockHttpServletResponse requestReset(String email, String ip) throws Exception {
        return post(RESET, Map.of("email", email), ip);
    }

    public MockHttpServletResponse verifyReset(String email, String code) throws Exception {
        return verifyReset(email, code, newIp());
    }

    public MockHttpServletResponse verifyReset(String email, String code, String ip) throws Exception {
        return post(RESET_VERIFY, Map.of("email", email, "code", code), ip);
    }

    /** Verifies the code and returns the reset token, failing the test when verify is not a 200.
     *  PT: Confere o código e devolve o token, falhando o teste quando o verify não é 200. */
    public String resetToken(String email, String code) throws Exception {
        var response = verifyReset(email, code);
        if (response.getStatus() != 200) {
            throw new AssertionError("verify answered " + response.getStatus());
        }
        return JSON.readTree(response.getContentAsString()).get("resetToken").asString();
    }

    public MockHttpServletResponse confirmReset(String resetToken, String newPassword) throws Exception {
        return confirmReset(resetToken, newPassword, newIp());
    }

    public MockHttpServletResponse confirmReset(String resetToken, String newPassword, String ip) throws Exception {
        return post(RESET_CONFIRM, Map.of("resetToken", resetToken, "newPassword", newPassword), ip);
    }

    public MockHttpServletResponse sendVerification(String accessToken) throws Exception {
        return perform(MockMvcRequestBuilders.post(VERIFY).header(HttpHeaders.AUTHORIZATION, "Bearer " + accessToken));
    }

    public MockHttpServletResponse confirmVerification(String accessToken, String code) throws Exception {
        return perform(MockMvcRequestBuilders.post(VERIFY_CONFIRM)
                .header(HttpHeaders.AUTHORIZATION, "Bearer " + accessToken)
                .contentType(MediaType.APPLICATION_JSON)
                .content(JSON.writeValueAsString(Map.of("code", code))));
    }

    public MockHttpServletResponse me(String accessToken) throws Exception {
        return perform(MockMvcRequestBuilders.get(ME).header(HttpHeaders.AUTHORIZATION, "Bearer " + accessToken));
    }

    /** The code of the latest email to {@code email} whose subject contains {@code subjectPart}.
     *  PT: O código do último email para {@code email} cujo assunto contém {@code subjectPart}. */
    public String codeOf(String email, String subjectPart) {
        var messages = mail.sent();
        for (int i = messages.size() - 1; i >= 0; i--) {
            var message = messages.get(i);
            if (message.to().equals(email) && message.subject().contains(subjectPart)) {
                var matcher = SIX_DIGITS.matcher(message.text());
                if (matcher.find()) {
                    return matcher.group(1);
                }
            }
        }
        throw new AssertionError("no \"" + subjectPart + "\" email with a code for the address");
    }

    public String resetCodeOf(String email) {
        return codeOf(email, "password reset");
    }

    public String verificationCodeOf(String email) {
        return codeOf(email, "verification");
    }

    public long countSubject(String email, String subjectPart) {
        return mail.sent().stream()
                .filter(m -> m.to().equals(email) && m.subject().contains(subjectPart)).count();
    }

    private MockHttpServletResponse post(String path, Map<String, String> body, String ip) throws Exception {
        var request = MockMvcRequestBuilders.post(path)
                .contentType(MediaType.APPLICATION_JSON)
                .content(JSON.writeValueAsString(body));
        if (ip != null) {
            request = request.with(r -> {
                r.setRemoteAddr(ip);
                return r;
            });
        }
        return perform(request);
    }

    private MockHttpServletResponse perform(MockHttpServletRequestBuilder request) throws Exception {
        return mvc.perform(request).andReturn().getResponse();
    }
}
