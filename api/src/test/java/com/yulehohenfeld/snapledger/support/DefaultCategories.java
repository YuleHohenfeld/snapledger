package com.yulehohenfeld.snapledger.support;

import java.util.List;
import java.util.UUID;

/**
 * The ids and keys seeded by V7, for tests.
 *
 * <p>PT: Os ids e as chaves do seed da V7, para os testes.
 */
public final class DefaultCategories {

    public static final UUID FOOD = UUID.fromString("c0000000-0000-4000-8000-000000000001");
    public static final UUID GROCERIES = UUID.fromString("c0000000-0000-4000-8000-000000000002");

    /** Seeded names in the order GET /categories returns them (by name, case-insensitive). PT: Nomes do seed na ordem do GET /categories. */
    public static final List<String> NAMES_BY_NAME = List.of(
            "Education", "Food", "Groceries", "Health", "Housing", "Leisure", "Other", "Transport");

    private DefaultCategories() {
    }
}
