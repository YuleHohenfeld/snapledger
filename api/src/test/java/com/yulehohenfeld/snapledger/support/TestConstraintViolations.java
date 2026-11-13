package com.yulehohenfeld.snapledger.support;

import java.sql.SQLException;

import org.hibernate.exception.ConstraintViolationException;
import org.springframework.dao.DataIntegrityViolationException;

/**
 * Constraint violations shaped like the real ones, for tests that need one without a database.
 *
 * <p>PT: Violações de constraint no formato das reais, para testes que precisam de uma sem banco.
 */
public final class TestConstraintViolations {

    private TestConstraintViolations() {
    }

    /**
     * What Hibernate throws: the name it extracted ({@code null} = none), over a driver exception.
     *
     * <p>PT: O que o Hibernate lança: o nome que ele extraiu ({@code null} = nenhum), sobre uma
     * exceção do driver.
     */
    public static ConstraintViolationException hibernate(String constraint) {
        var sql = new SQLException("ERROR: violates constraint \"" + constraint + "\"", "23505");
        return new ConstraintViolationException("could not execute statement", sql, constraint);
    }

    /**
     * What a repository proxy throws after Spring's translation.
     *
     * <p>PT: O que o proxy de um repository lança depois da tradução do Spring.
     */
    public static DataIntegrityViolationException translated(String constraint) {
        return new DataIntegrityViolationException("could not execute statement", hibernate(constraint));
    }
}
