package com.yulehohenfeld.snapledger.support;

import java.util.Map;
import java.util.UUID;

import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpMethod;
import org.springframework.http.MediaType;
import org.springframework.mock.web.MockHttpServletResponse;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.request.MockMvcRequestBuilders;

import tools.jackson.databind.JsonNode;
import tools.jackson.databind.json.JsonMapper;

/**
 * A registered user driving the API through MockMvc with a real access token, for integration tests.
 *
 * <p>PT: Um usuário cadastrado usando a API pelo MockMvc com um token de acesso real, para testes
 * de integração.
 */
public final class ApiSession {

    public static final JsonMapper JSON = JsonMapper.builder().build();

    private final MockMvc mvc;
    private final String accessToken;
    private final UUID userId;

    private ApiSession(MockMvc mvc, String accessToken, UUID userId) {
        this.mvc = mvc;
        this.accessToken = accessToken;
        this.userId = userId;
    }

    /** Registers a new user with a random email and password. PT: Cadastra um usuário novo com email e senha aleatórios. */
    public static ApiSession register(MockMvc mvc) throws Exception {
        var body = JSON.writeValueAsString(Map.of("name", "Test User",
                "email", "user-" + UUID.randomUUID() + "@example.com", "password", "pw-" + UUID.randomUUID()));
        var response = mvc.perform(MockMvcRequestBuilders.post("/api/v1/auth/register")
                .contentType(MediaType.APPLICATION_JSON).content(body)).andReturn().getResponse();
        if (response.getStatus() != 201) {
            throw new IllegalStateException("register failed with " + response.getStatus());
        }
        var tree = JSON.readTree(response.getContentAsString());
        return new ApiSession(mvc, tree.get("tokens").get("accessToken").asString(),
                UUID.fromString(tree.get("user").get("id").asString()));
    }

    public UUID userId() {
        return userId;
    }

    public MockHttpServletResponse get(String path) throws Exception {
        return send(HttpMethod.GET, path, null);
    }

    public MockHttpServletResponse post(String path, String body) throws Exception {
        return send(HttpMethod.POST, path, body);
    }

    public MockHttpServletResponse put(String path, String body) throws Exception {
        return send(HttpMethod.PUT, path, body);
    }

    public MockHttpServletResponse patch(String path, String body) throws Exception {
        return send(HttpMethod.PATCH, path, body);
    }

    public MockHttpServletResponse delete(String path) throws Exception {
        return send(HttpMethod.DELETE, path, null);
    }

    private MockHttpServletResponse send(HttpMethod method, String path, String body) throws Exception {
        var request = MockMvcRequestBuilders.request(method, path)
                .header(HttpHeaders.AUTHORIZATION, "Bearer " + accessToken);
        if (body != null) {
            request.contentType(MediaType.APPLICATION_JSON).content(body);
        }
        return mvc.perform(request).andReturn().getResponse();
    }

    /** The JSON body of POST /categories. PT: O corpo JSON do POST /categories. */
    public static String nameBody(String name) {
        return JSON.writeValueAsString(Map.of("name", name));
    }

    public static JsonNode json(MockHttpServletResponse response) throws Exception {
        return JSON.readTree(response.getContentAsString());
    }

    public static String type(MockHttpServletResponse response) throws Exception {
        return json(response).get("type").asString();
    }
}
