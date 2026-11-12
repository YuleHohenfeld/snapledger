package com.yulehohenfeld.snapledger.shared.error;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import java.net.URI;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.CsvSource;
import org.junit.jupiter.params.provider.ValueSource;
import org.springframework.http.HttpStatus;
import org.springframework.http.HttpStatusCode;

class ProblemFactoryTest {

    @Test
    void buildsTypeFixedTitleAndInstance() {
        var problem = ProblemFactory.create(HttpStatus.CONFLICT, "category-name-taken", "Name taken.", "/api/v1/categories");

        assertThat(problem.getType()).isEqualTo(URI.create("urn:snapledger:problem:category-name-taken"));
        assertThat(problem.getTitle()).isEqualTo("Category name taken");
        assertThat(problem.getStatus()).isEqualTo(409);
        assertThat(problem.getDetail()).isEqualTo("Name taken.");
        assertThat(problem.getInstance()).isEqualTo(URI.create("/api/v1/categories"));
    }

    /**
     * Copied from docs/api-contract.md "Errors": a change there must break this test.
     *
     * <p>PT: Copiado da seção "Errors" do docs/api-contract.md: uma mudança lá precisa quebrar este
     * teste.
     */
    @ParameterizedTest
    @CsvSource({
            "validation-error, Validation failed",
            "unauthorized, Unauthorized",
            "invalid-credentials, Invalid credentials",
            "invalid-refresh-token, Invalid refresh token",
            "forbidden, Forbidden",
            "default-category-read-only, Default category is read-only",
            "not-found, Not found",
            "method-not-allowed, Method not allowed",
            "not-acceptable, Not acceptable",
            "email-already-registered, Email already registered",
            "category-name-taken, Category name taken",
            "category-in-use, Category in use",
            "unsupported-media-type, Unsupported media type",
            "internal-error, Internal error"})
    void everyContractSlugHasItsTypeAndFixedTitle(String slug, String title) {
        var problem = ProblemFactory.create(HttpStatus.BAD_REQUEST, slug, "x", "/");

        assertThat(problem.getType()).isEqualTo(URI.create("urn:snapledger:problem:" + slug));
        assertThat(problem.getTitle()).isEqualTo(title);
    }

    @Test
    void knowsExactlyTheFourteenContractSlugs() {
        assertThat(ProblemFactory.knownSlugs()).hasSize(14);
    }

    @Test
    void rejectsSlugThatIsNotInTheContract() {
        assertThatThrownBy(() -> ProblemFactory.create(HttpStatus.BAD_REQUEST, "made-up", "x", "/"))
                .isInstanceOf(IllegalArgumentException.class);
    }

    @Test
    void requireKnownSlugReturnsAKnownSlugAndRejectsUnknownOrNull() {
        assertThat(ProblemFactory.requireKnownSlug("not-found")).isEqualTo("not-found");
        assertThatThrownBy(() -> ProblemFactory.requireKnownSlug("made-up"))
                .isInstanceOf(IllegalArgumentException.class);
        assertThatThrownBy(() -> ProblemFactory.requireKnownSlug(null))
                .isInstanceOf(IllegalArgumentException.class);
    }

    @ParameterizedTest
    @CsvSource({
            "400, validation-error, Validation failed",
            "401, unauthorized, Unauthorized",
            "403, forbidden, Forbidden",
            "404, not-found, Not found",
            "405, method-not-allowed, Method not allowed",
            "406, not-acceptable, Not acceptable",
            "415, unsupported-media-type, Unsupported media type"})
    void forStatusUsesTheContractSlugOfFrameworkStatuses(int status, String slug, String title) {
        var problem = ProblemFactory.forStatus(HttpStatusCode.valueOf(status), "/api/v1/x");

        assertThat(problem).isNotNull();
        assertThat(problem.getStatus()).isEqualTo(status);
        assertThat(problem.getType()).isEqualTo(URI.create("urn:snapledger:problem:" + slug));
        assertThat(problem.getTitle()).isEqualTo(title);
        assertThat(problem.getDetail()).isNotBlank();
        assertThat(problem.getInstance()).isEqualTo(URI.create("/api/v1/x"));
    }

    // 5xx needs an errorId and a log line, so InternalErrors builds it, never forStatus.
    // PT: 5xx precisa de um errorId e de uma linha de log, então o InternalErrors o monta, nunca o
    //     forStatus.
    @ParameterizedTest
    @ValueSource(ints = {409, 413, 414, 431, 499, 500, 503})
    void forStatusReturnsNullForStatusesWithoutAFrameworkSlug(int status) {
        assertThat(ProblemFactory.forStatus(HttpStatusCode.valueOf(status), "/x")).isNull();
    }

    @Test
    void forFrameworkStatusUsesTheContractSlugWhenThereIsOne() {
        var problem = ProblemFactory.forFrameworkStatus(HttpStatus.METHOD_NOT_ALLOWED, "/api/v1/x");

        assertThat(problem.getType()).isEqualTo(URI.create("urn:snapledger:problem:method-not-allowed"));
        assertThat(problem.getStatus()).isEqualTo(405);
    }

    @ParameterizedTest
    @ValueSource(ints = {409, 413, 431})
    void forFrameworkStatusFallsBackToAboutBlank(int status) {
        var problem = ProblemFactory.forFrameworkStatus(HttpStatusCode.valueOf(status), "/api/v1/x");

        assertThat(problem.getType()).isEqualTo(URI.create("about:blank"));
        assertThat(problem.getStatus()).isEqualTo(status);
        assertThat(problem.getTitle()).isEqualTo(HttpStatus.valueOf(status).getReasonPhrase());
        assertThat(problem.getInstance()).isEqualTo(URI.create("/api/v1/x"));
    }

    @Test
    void aboutBlankUsesTheStandardReasonPhraseAndNoContractType() {
        var problem = ProblemFactory.aboutBlank(HttpStatus.CONTENT_TOO_LARGE, "/api/v1/x");

        assertThat(problem.getType()).isEqualTo(URI.create("about:blank"));
        assertThat(problem.getTitle()).isEqualTo(HttpStatus.CONTENT_TOO_LARGE.getReasonPhrase());
        assertThat(problem.getStatus()).isEqualTo(413);
        assertThat(problem.getDetail()).isNull();
        assertThat(problem.getInstance()).isEqualTo(URI.create("/api/v1/x"));
    }

    @Test
    void aboutBlankForAnUnregisteredStatusHasNoTitle() {
        var problem = ProblemFactory.aboutBlank(HttpStatusCode.valueOf(499), "/x");

        assertThat(problem.getStatus()).isEqualTo(499);
        assertThat(problem.getType()).isEqualTo(URI.create("about:blank"));
        assertThat(problem.getTitle()).isNull();
    }

    @Test
    void omitsInstanceWhenPathIsNotAValidUri() {
        var problem = ProblemFactory.create(HttpStatus.NOT_FOUND, "not-found", "x", "/a b|c");

        assertThat(problem.getInstance()).isNull();
    }
}
