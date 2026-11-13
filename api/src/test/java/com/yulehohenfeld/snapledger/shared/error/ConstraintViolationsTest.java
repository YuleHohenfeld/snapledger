package com.yulehohenfeld.snapledger.shared.error;

import static org.assertj.core.api.Assertions.assertThat;

import java.sql.SQLException;

import org.junit.jupiter.api.Test;
import org.springframework.dao.DataIntegrityViolationException;

import com.yulehohenfeld.snapledger.support.TestConstraintViolations;

/**
 * Constraint recognition by exact name, as services use it to turn one violation into a 409.
 *
 * <p>PT: Reconhecimento de constraint pelo nome exato, como os Services usam para transformar uma
 * violação num 409.
 */
class ConstraintViolationsTest {

    @Test
    void matchesTheExactNameAnywhereInTheCauseChain() {
        var failure = new DataIntegrityViolationException("x", hibernateViolation("uk_users_email"));

        assertThat(ConstraintViolations.violates(failure, "uk_users_email")).isTrue();
    }

    @Test
    void doesNotMatchAnotherOrASimilarName() {
        var failure = new DataIntegrityViolationException("x", hibernateViolation("uk_users_email_lower"));

        assertThat(ConstraintViolations.violates(failure, "uk_users_email")).isFalse();
        assertThat(ConstraintViolations.violates(failure, "uk_users")).isFalse();
    }

    // The name comes from Hibernate's parsed field, never from text: a message that quotes the name
    // is not enough.
    // PT: O nome vem do campo que o Hibernate extraiu, nunca do texto: uma mensagem que cita o nome
    //     não basta.
    @Test
    void ignoresMessagesThatOnlyMentionTheName() {
        var failure = new DataIntegrityViolationException("violates \"uk_users_email\"",
                new SQLException("violates unique constraint \"uk_users_email\"", "23505"));

        assertThat(ConstraintViolations.violates(failure, "uk_users_email")).isFalse();
    }

    @Test
    void nullInputsAreNeverAMatch() {
        assertThat(ConstraintViolations.violates(null, "uk_users_email")).isFalse();
        assertThat(ConstraintViolations.violates(hibernateViolation(null), null)).isFalse();
        assertThat(ConstraintViolations.violates(hibernateViolation(null), "uk_users_email")).isFalse();
    }

    @Test
    void aGraphTooBigToInspectIsNotAMatchAndDoesNotThrow() {
        Throwable failure = hibernateViolation("uk_users_email");
        for (int i = 0; i <= InternalErrors.MAX_NODES; i++) {
            failure = new RuntimeException("wrapper", failure);
        }

        assertThat(ConstraintViolations.violates(failure, "uk_users_email")).isFalse();
    }

    private static Throwable hibernateViolation(String name) {
        return TestConstraintViolations.hibernate(name);
    }
}
