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
    void authErrorsUseTheirContractStatusAndSlug() {
        assertThat(new UnauthorizedException())
                .returns(HttpStatus.UNAUTHORIZED, ApiException::status)
                .returns("unauthorized", ApiException::slug);
        assertThat(new InvalidCredentialsException())
                .returns(HttpStatus.UNAUTHORIZED, ApiException::status)
                .returns("invalid-credentials", ApiException::slug);
        assertThat(new EmailAlreadyRegisteredException())
                .returns(HttpStatus.CONFLICT, ApiException::status)
                .returns("email-already-registered", ApiException::slug);
    }

    // Unknown email and wrong password must be indistinguishable: one class, no arguments, so two
    // instances always carry the same detail and nothing about the attempt.
    // PT: Email desconhecido e senha errada precisam ser indistinguíveis: uma classe, sem argumentos,
    //     então duas instâncias sempre levam o mesmo detalhe e nada sobre a tentativa.
    @Test
    void invalidCredentialsAlwaysHasTheSameDetail() {
        assertThat(new InvalidCredentialsException().getMessage())
                .isEqualTo(new InvalidCredentialsException().getMessage())
                .doesNotContain("@");
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
