package com.yulehohenfeld.snapledger.shared.error;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import java.net.URI;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.CsvSource;
import org.springframework.http.HttpStatus;

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

    /** Copied from docs/api-contract.md "Errors": a change there must break this test. */
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

    @Test
    void omitsInstanceWhenPathIsNotAValidUri() {
        var problem = ProblemFactory.create(HttpStatus.NOT_FOUND, "not-found", "x", "/a b|c");

        assertThat(problem.getInstance()).isNull();
    }
}
