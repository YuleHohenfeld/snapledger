package com.yulehohenfeld.snapledger.category.repository;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import java.time.Instant;
import java.util.UUID;

import jakarta.persistence.PersistenceException;
import jakarta.persistence.Query;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.CsvSource;
import org.junit.jupiter.params.provider.ValueSource;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.data.jpa.test.autoconfigure.DataJpaTest;
import org.springframework.boot.jdbc.test.autoconfigure.AutoConfigureTestDatabase;
import org.springframework.boot.jpa.test.autoconfigure.TestEntityManager;
import org.springframework.context.annotation.Import;
import org.springframework.dao.DataIntegrityViolationException;

import com.yulehohenfeld.snapledger.category.entity.Category;
import com.yulehohenfeld.snapledger.shared.error.ConstraintViolations;
import com.yulehohenfeld.snapledger.support.DefaultCategories;
import com.yulehohenfeld.snapledger.support.TestPasswordHashes;
import com.yulehohenfeld.snapledger.support.TestcontainersConfiguration;
import com.yulehohenfeld.snapledger.user.entity.User;

/**
 * V6 and V7 against a real PostgreSQL: the mapping passes ddl-auto=validate, the queries scope by
 * user and the constraints refuse what the contract forbids, even through plain SQL.
 *
 * <p>PT: A V6 e a V7 contra um PostgreSQL real: o mapeamento passa no ddl-auto=validate, as queries
 * filtram por usuário e as constraints recusam o que o contrato proíbe, mesmo por SQL puro.
 */
@DataJpaTest
@Import(TestcontainersConfiguration.class)
@AutoConfigureTestDatabase(replace = AutoConfigureTestDatabase.Replace.NONE)
class CategoryRepositoryTest {

    static final Instant NOW = Instant.parse("2026-11-12T10:00:00Z");

    @Autowired
    CategoryRepository categories;

    @Autowired
    TestEntityManager entityManager;

    UUID ana;
    UUID bruno;

    @BeforeEach
    void createUsers() {
        ana = persistUser("ana@example.com");
        bruno = persistUser("bruno@example.com");
    }

    @Test
    void seedHasTheEightDefaultsWithStableKeys() {
        var visible = categories.findVisible(ana);

        assertThat(visible).extracting(Category::getName).containsExactlyElementsOf(DefaultCategories.NAMES_BY_NAME);
        assertThat(visible).allMatch(Category::isDefault);
        assertThat(visible).extracting(Category::getKey)
                .containsExactly("education", "food", "groceries", "health", "housing", "leisure", "other", "transport");
    }

    @Test
    void findVisibleListsDefaultsFirstThenOwnByLowerCaseNameAndHidesOtherUsers() {
        categories.saveAndFlush(Category.createOwn(ana, "zebra", NOW));
        categories.saveAndFlush(Category.createOwn(ana, "Banana", NOW));
        categories.saveAndFlush(Category.createOwn(ana, "apple", NOW));
        categories.saveAndFlush(Category.createOwn(bruno, "Secret", NOW));

        var names = categories.findVisible(ana).stream().map(Category::getName).toList();

        assertThat(names).hasSize(11);
        assertThat(names.subList(0, 8)).containsExactlyElementsOf(DefaultCategories.NAMES_BY_NAME);
        assertThat(names.subList(8, 11)).containsExactly("apple", "Banana", "zebra");
    }

    @Test
    void findVisibleByIdFindsDefaultsAndOwnButNotAnotherUsersCategory() {
        var own = categories.saveAndFlush(Category.createOwn(ana, "Pets", NOW));
        var brunos = categories.saveAndFlush(Category.createOwn(bruno, "Gym", NOW));
        entityManager.clear();

        assertThat(categories.findVisibleById(DefaultCategories.FOOD, ana)).isPresent();
        assertThat(categories.findVisibleById(own.getId(), ana)).isPresent();
        assertThat(categories.findVisibleById(brunos.getId(), ana)).isEmpty();
        assertThat(categories.findVisibleById(own.getId(), bruno)).isEmpty();
        assertThat(categories.findVisibleById(UUID.randomUUID(), ana)).isEmpty();
    }

    @Test
    void existsDefaultNamedIgnoreCaseSeesOnlyDefaults() {
        categories.saveAndFlush(Category.createOwn(ana, "Pets", NOW));

        assertThat(categories.existsDefaultNamedIgnoreCase("food")).isTrue();
        assertThat(categories.existsDefaultNamedIgnoreCase("GROCERIES")).isTrue();
        assertThat(categories.existsDefaultNamedIgnoreCase("Pets")).isFalse();
    }

    @Test
    void sameNameInAnyCaseTwiceForOneUserViolatesTheUniqueIndex() {
        categories.saveAndFlush(Category.createOwn(ana, "Pets", NOW));

        assertThatThrownBy(() -> categories.saveAndFlush(Category.createOwn(ana, "pETS", NOW)))
                .isInstanceOf(DataIntegrityViolationException.class)
                .matches(e -> ConstraintViolations.violates(e, "uk_categories_user_name"));
    }

    @Test
    void twoUsersMayUseTheSameName() {
        categories.saveAndFlush(Category.createOwn(ana, "Pets", NOW));

        assertThat(categories.saveAndFlush(Category.createOwn(bruno, "Pets", NOW))).isNotNull();
    }

    // The database does not stop an own category from using a default name; the service does (documented in the note).
    // PT: O banco não impede uma categoria própria com nome de padrão; o service impede (documentado na nota).
    @Test
    void databaseAllowsAnOwnCategoryNamedLikeADefault() {
        assertThat(insert(ana, null, "Food").executeUpdate()).isEqualTo(1);
    }

    @Test
    void secondDefaultWithTheSameNameInAnyCaseViolatesTheDefaultNameIndex() {
        assertThatThrownBy(insert(null, null, "fOOD")::executeUpdate)
                .isInstanceOf(PersistenceException.class)
                .rootCause().hasMessageContaining("uk_categories_default_name");
    }

    @ParameterizedTest(name = "{0}")
    @CsvSource(delimiter = '|', textBlock = """
            empty name            | ''     | ck_categories_name_trimmed
            leading space         | ' x'   | ck_categories_name_trimmed
            trailing space        | 'x '   | ck_categories_name_trimmed
            """)
    void databaseRejectsAnUntrimmedName(String description, String name, String constraint) {
        assertThatThrownBy(insert(ana, null, name)::executeUpdate)
                .isInstanceOf(PersistenceException.class)
                .rootCause().hasMessageContaining(constraint);
    }

    @ParameterizedTest
    @ValueSource(strings = {"Pe\u0001ts", "Pe\u001bts", "Pe\nts", "Pe\u007fts", "Pe\u0085ts", "Pe\u009fts"})
    void databaseRejectsControlCharactersInTheName(String name) {
        assertThatThrownBy(insert(ana, null, name)::executeUpdate)
                .isInstanceOf(PersistenceException.class)
                .rootCause().hasMessageContaining("ck_categories_name_no_control_chars");
    }

    @Test
    void databaseRejectsANameLongerThan40CodePointsAndAcceptsExactly40() {
        assertThat(insert(ana, null, "😀".repeat(40)).executeUpdate()).isEqualTo(1);
    }

    @Test
    void databaseRejectsANameOf41CodePoints() {
        assertThatThrownBy(insert(ana, null, "😀".repeat(41))::executeUpdate)
                .isInstanceOf(PersistenceException.class)
                .rootCause().hasMessageContaining("character varying(40)");
    }

    @Test
    void databaseRejectsAKeyOnAnOwnCategory() {
        assertThatThrownBy(insert(ana, "pets", "Pets")::executeUpdate)
                .isInstanceOf(PersistenceException.class)
                .rootCause().hasMessageContaining("ck_categories_key_only_default");
    }

    @ParameterizedTest
    @ValueSource(strings = {"Bad", "1abc", "with space", "a-b", ""})
    void databaseRejectsAMalformedKey(String key) {
        assertThatThrownBy(insert(null, key, "Newdefault")::executeUpdate)
                .isInstanceOf(PersistenceException.class)
                .rootCause().hasMessageContaining("ck_categories_key_format");
    }

    @Test
    void databaseRejectsADuplicateKey() {
        assertThatThrownBy(insert(null, "food", "Another")::executeUpdate)
                .isInstanceOf(PersistenceException.class)
                .rootCause().hasMessageContaining("uk_categories_key");
    }

    private UUID persistUser(String email) {
        var user = User.register("Test", email, TestPasswordHashes.BCRYPT, "BRL", NOW);
        entityManager.persistAndFlush(user);
        return user.getId();
    }

    // Null columns are written as SQL null, because a null JDBC parameter has no type to bind.
    // PT: Colunas nulas viram null no SQL, porque um parâmetro JDBC nulo não tem tipo para o bind.
    private Query insert(UUID userId, String key, String name) {
        var query = entityManager.getEntityManager().createNativeQuery("""
                insert into categories (id, user_id, key, name, created_at)
                values (:id, %s, %s, :name, :now)
                """.formatted(userId == null ? "null" : ":userId", key == null ? "null" : ":key"))
                .setParameter("id", UUID.randomUUID())
                .setParameter("name", name)
                .setParameter("now", NOW);
        if (userId != null) {
            query.setParameter("userId", userId);
        }
        if (key != null) {
            query.setParameter("key", key);
        }
        return query;
    }
}
