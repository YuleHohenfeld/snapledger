package com.yulehohenfeld.snapledger.shared.error;

/**
 * Recognizes a violated database constraint by its exact name, never by message.
 *
 * <p>PT: Reconhece uma constraint do banco violada pelo nome exato, nunca pela mensagem.
 * Notes: docs/code-notes/security.md#constraintviolations
 */
public final class ConstraintViolations {

    private ConstraintViolations() {
    }

    /**
     * True only when {@code failure} carries a violation of exactly {@code constraint}; never throws.
     *
     * <p>PT: Verdadeiro só quando {@code failure} traz uma violação exatamente de {@code constraint};
     * nunca lança exceção.
     */
    public static boolean violates(Throwable failure, String constraint) {
        if (failure == null || constraint == null) {
            return false;
        }
        try {
            return constraint.equals(InternalErrors.constraintName(failure));
        } catch (InternalErrors.TraversalLimitExceeded tooBig) {
            return false;
        }
    }
}
