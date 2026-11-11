package com.yulehohenfeld.snapledger.shared.error;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import org.junit.jupiter.api.Test;
import org.springframework.http.HttpStatus;

class ApiExceptionTest {

    @Test
    void subclassWithAContractSlugKeepsStatusSlugAndDetail() {
        var ex = new NotFoundException();

        assertThat(ex.status()).isEqualTo(HttpStatus.NOT_FOUND);
        assertThat(ex.slug()).isEqualTo("not-found");
        assertThat(ex.getMessage()).isEqualTo("Resource not found.");
    }

    @Test
    void subclassWithASlugMissingFromTheContractFailsAtConstruction() {
        assertThatThrownBy(UnknownSlugException::new)
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("made-up");
    }

    static class UnknownSlugException extends ApiException {

        UnknownSlugException() {
            super(HttpStatus.CONFLICT, "made-up", "Never built.");
        }
    }
}
