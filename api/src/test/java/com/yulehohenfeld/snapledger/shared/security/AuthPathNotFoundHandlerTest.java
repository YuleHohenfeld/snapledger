package com.yulehohenfeld.snapledger.shared.security;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.Test;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.mock.web.MockHttpServletResponse;
import org.springframework.security.access.AccessDeniedException;
import org.springframework.security.authentication.InsufficientAuthenticationException;

import com.jayway.jsonpath.JsonPath;

/** Chain 1 has no authentication, so the access-denied branch is exercised directly. */
class AuthPathNotFoundHandlerTest {

    private final AuthPathNotFoundHandler handler = new AuthPathNotFoundHandler();

    @Test
    void entryPointWritesNotFoundWithoutWwwAuthenticate() throws Exception {
        var response = new MockHttpServletResponse();

        handler.commence(new MockHttpServletRequest("GET", "/api/v1/auth/login"), response,
                new InsufficientAuthenticationException("internal reason"));

        assertNotFound(response, "/api/v1/auth/login");
    }

    @Test
    void accessDeniedHandlerWritesTheSameNotFound() throws Exception {
        var response = new MockHttpServletResponse();

        handler.handle(new MockHttpServletRequest("PUT", "/api/v1/auth/logout"), response,
                new AccessDeniedException("internal reason"));

        assertNotFound(response, "/api/v1/auth/logout");
    }

    @Test
    void doesNothingWhenResponseIsAlreadyCommitted() throws Exception {
        var response = new MockHttpServletResponse();
        response.setCommitted(true);

        handler.commence(new MockHttpServletRequest(), response, new InsufficientAuthenticationException("x"));

        assertThat(response.getContentAsString()).isEmpty();
    }

    private static void assertNotFound(MockHttpServletResponse response, String path) throws Exception {
        assertThat(response.getStatus()).isEqualTo(404);
        assertThat(response.getHeader(HttpHeaders.WWW_AUTHENTICATE)).isNull();
        assertThat(MediaType.parseMediaType(response.getContentType()).isCompatibleWith(MediaType.APPLICATION_PROBLEM_JSON))
                .isTrue();
        var body = response.getContentAsString();
        assertThat((String) JsonPath.read(body, "$.type")).isEqualTo("urn:snapledger:problem:not-found");
        assertThat((String) JsonPath.read(body, "$.title")).isEqualTo("Not found");
        assertThat((String) JsonPath.read(body, "$.instance")).isEqualTo(path);
        assertThat(body).doesNotContain("internal reason");
    }
}
