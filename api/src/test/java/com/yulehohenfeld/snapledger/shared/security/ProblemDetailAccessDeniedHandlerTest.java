package com.yulehohenfeld.snapledger.shared.security;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.Test;
import org.springframework.http.MediaType;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.mock.web.MockHttpServletResponse;
import org.springframework.security.access.AccessDeniedException;

import com.jayway.jsonpath.JsonPath;

/**
 * No chain rule produces 403 yet, so the handler is exercised directly.
 *
 * <p>PT: Nenhuma regra das cadeias produz 403 ainda, então o handler é exercitado diretamente.
 */
class ProblemDetailAccessDeniedHandlerTest {

    private final ProblemDetailAccessDeniedHandler handler = new ProblemDetailAccessDeniedHandler();

    @Test
    void writesForbiddenProblemDetail() throws Exception {
        var request = new MockHttpServletRequest("DELETE", "/api/v1/categories/123");
        var response = new MockHttpServletResponse();

        handler.handle(request, response, new AccessDeniedException("internal reason"));

        assertThat(response.getStatus()).isEqualTo(403);
        assertThat(MediaType.parseMediaType(response.getContentType()))
                .satisfies(type -> assertThat(type.isCompatibleWith(MediaType.APPLICATION_PROBLEM_JSON)).isTrue());
        var body = response.getContentAsString();
        assertThat((String) JsonPath.read(body, "$.type")).isEqualTo("urn:snapledger:problem:forbidden");
        assertThat((String) JsonPath.read(body, "$.title")).isEqualTo("Forbidden");
        assertThat((Integer) JsonPath.read(body, "$.status")).isEqualTo(403);
        assertThat((String) JsonPath.read(body, "$.instance")).isEqualTo("/api/v1/categories/123");
        assertThat(body).doesNotContain("internal reason");
    }

    @Test
    void doesNothingWhenResponseIsAlreadyCommitted() throws Exception {
        var response = new MockHttpServletResponse();
        response.setCommitted(true);

        handler.handle(new MockHttpServletRequest(), response, new AccessDeniedException("x"));

        assertThat(response.getContentAsString()).isEmpty();
    }
}
