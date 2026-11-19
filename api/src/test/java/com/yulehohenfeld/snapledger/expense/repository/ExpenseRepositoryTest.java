package com.yulehohenfeld.snapledger.expense.repository;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import java.math.BigDecimal;
import java.time.Instant;
import java.time.LocalDate;
import java.util.Comparator;
import java.util.UUID;

import jakarta.persistence.PersistenceException;
import jakarta.persistence.Query;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.data.jpa.test.autoconfigure.DataJpaTest;
import org.springframework.boot.jdbc.test.autoconfigure.AutoConfigureTestDatabase;
import org.springframework.boot.jpa.test.autoconfigure.TestEntityManager;
import org.springframework.context.annotation.Import;

import com.yulehohenfeld.snapledger.category.entity.Category;
import com.yulehohenfeld.snapledger.category.repository.CategoryRepository;
import com.yulehohenfeld.snapledger.expense.entity.Expense;
import com.yulehohenfeld.snapledger.support.DefaultCategories;
import com.yulehohenfeld.snapledger.support.TestPasswordHashes;
import com.yulehohenfeld.snapledger.support.TestcontainersConfiguration;
import com.yulehohenfeld.snapledger.user.entity.User;

/**
 * V8 against a real PostgreSQL: month queries, ownership in the query, ordering, and every CHECK
 * and foreign key through plain SQL.
 *
 * <p>PT: A V8 contra um PostgreSQL real: consultas do mês, posse na query, ordenação, e cada CHECK
 * e chave estrangeira por SQL puro.
 */
@DataJpaTest
@Import(TestcontainersConfiguration.class)
@AutoConfigureTestDatabase(replace = AutoConfigureTestDatabase.Replace.NONE)
class ExpenseRepositoryTest {

    static final Instant NOW = Instant.parse("2026-11-12T10:00:00Z");

    @Autowired
    ExpenseRepository expenses;

    @Autowired
    CategoryRepository categories;

    @Autowired
    TestEntityManager entityManager;

    UUID ana;
    UUID bruno;
    Category food;
    Category groceries;

    @BeforeEach
    void createFixtures() {
        ana = persistUser("ana@example.com");
        bruno = persistUser("bruno@example.com");
        food = categories.findById(DefaultCategories.FOOD).orElseThrow();
        groceries = categories.findById(DefaultCategories.GROCERIES).orElseThrow();
    }

    @Test
    void savesAnExpenseAndReadsItBackWithItsCategoryAndExactAmount() {
        var saved = save(ana, food, "12.5", "Lunch", LocalDate.of(2026, 11, 8), NOW);
        entityManager.clear();

        var found = expenses.findByIdAndUserId(saved.getId(), ana).orElseThrow();

        assertThat(found.getAmount()).isEqualByComparingTo("12.50");
        assertThat(found.getAmount().scale()).isEqualTo(2);
        assertThat(found.getDescription()).isEqualTo("Lunch");
        assertThat(found.getExpenseDate()).isEqualTo(LocalDate.of(2026, 11, 8));
        assertThat(found.getCategory().getId()).isEqualTo(DefaultCategories.FOOD);
        assertThat(found.getCreatedAt()).isEqualTo(NOW);
        assertThat(found.getUpdatedAt()).isEqualTo(NOW);
    }

    @Test
    void findByIdAndUserIdIsEmptyForAnotherUser() {
        var saved = save(ana, food, "1", "Mine", LocalDate.of(2026, 11, 8), NOW);
        entityManager.clear();

        assertThat(expenses.findByIdAndUserId(saved.getId(), bruno)).isEmpty();
    }

    @Test
    void monthIncludesFirstAndLastDayAndExcludesTheNeighbourMonths() {
        save(ana, food, "1", "before", LocalDate.of(2026, 10, 31), NOW);
        var first = save(ana, food, "1", "first", LocalDate.of(2026, 11, 1), NOW);
        var last = save(ana, food, "1", "last", LocalDate.of(2026, 11, 30), NOW);
        save(ana, food, "1", "after", LocalDate.of(2026, 12, 1), NOW);
        entityManager.clear();

        var found = expenses.findMonth(ana, LocalDate.of(2026, 11, 1), LocalDate.of(2026, 11, 30));

        assertThat(found).extracting(Expense::getId).containsExactly(last.getId(), first.getId());
    }

    @Test
    void monthIsOrderedByDateThenCreatedAtThenIdDescending() {
        var oldest = save(ana, food, "1", "a", LocalDate.of(2026, 11, 1), NOW);
        var newestDay = save(ana, food, "1", "b", LocalDate.of(2026, 11, 9), NOW);
        var sameDayEarlier = save(ana, food, "1", "c", LocalDate.of(2026, 11, 5), NOW);
        var sameDayLater = save(ana, food, "1", "d", LocalDate.of(2026, 11, 5), NOW.plusSeconds(60));
        var tieA = save(ana, food, "1", "e", LocalDate.of(2026, 11, 3), NOW);
        var tieB = save(ana, food, "1", "f", LocalDate.of(2026, 11, 3), NOW);
        entityManager.clear();
        var tieByIdDesc = java.util.stream.Stream.of(tieA, tieB)
                .sorted(Comparator.comparing(Expense::getId).reversed()).map(Expense::getId).toList();

        var ids = expenses.findMonth(ana, LocalDate.of(2026, 11, 1), LocalDate.of(2026, 11, 30))
                .stream().map(Expense::getId).toList();

        assertThat(ids).containsExactly(newestDay.getId(), sameDayLater.getId(), sameDayEarlier.getId(),
                tieByIdDesc.get(0), tieByIdDesc.get(1), oldest.getId());
    }

    @Test
    void monthNeverIncludesAnotherUsersExpenses() {
        save(bruno, food, "1", "theirs", LocalDate.of(2026, 11, 8), NOW);
        var mine = save(ana, food, "1", "mine", LocalDate.of(2026, 11, 8), NOW);
        entityManager.clear();

        assertThat(expenses.findMonth(ana, LocalDate.of(2026, 11, 1), LocalDate.of(2026, 11, 30)))
                .extracting(Expense::getId).containsExactly(mine.getId());
    }

    @Test
    void monthInCategoryFiltersByCategory() {
        var inFood = save(ana, food, "1", "f", LocalDate.of(2026, 11, 8), NOW);
        save(ana, groceries, "1", "g", LocalDate.of(2026, 11, 8), NOW);
        entityManager.clear();

        assertThat(expenses.findMonthInCategory(ana, LocalDate.of(2026, 11, 1), LocalDate.of(2026, 11, 30),
                DefaultCategories.FOOD)).extracting(Expense::getId).containsExactly(inFood.getId());
    }

    @Test
    void deleteByIdAndUserIdDeletesOnlyTheUsersOwnRow() {
        var saved = save(ana, food, "1", "mine", LocalDate.of(2026, 11, 8), NOW);

        assertThat(expenses.deleteByIdAndUserId(saved.getId(), bruno)).isZero();
        assertThat(expenses.deleteByIdAndUserId(saved.getId(), ana)).isEqualTo(1);
        assertThat(expenses.findByIdAndUserId(saved.getId(), ana)).isEmpty();
    }

    @ParameterizedTest
    @ValueSource(strings = {"0", "-1", "0.001"})
    void databaseRejectsANonPositiveAmount(String amount) {
        // numeric(12,2) rounds 0.001 to 0.00 before the CHECK sees it. PT: o numeric(12,2) arredonda 0.001 para 0.00 antes do CHECK.
        assertThatThrownBy(insert(ana, amount, "x", "2026-11-08", NOW, NOW)::executeUpdate)
                .isInstanceOf(PersistenceException.class)
                .rootCause().hasMessageContaining("ck_expenses_amount_positive");
    }

    @Test
    void databaseRejectsAnAmountBeyondNumeric12Scale2() {
        assertThatThrownBy(insert(ana, "10000000000.00", "x", "2026-11-08", NOW, NOW)::executeUpdate)
                .isInstanceOf(PersistenceException.class)
                .rootCause().hasMessageContaining("numeric field overflow");
    }

    @ParameterizedTest
    @ValueSource(strings = {"", " x", "x "})
    void databaseRejectsAnUntrimmedDescription(String description) {
        assertThatThrownBy(insert(ana, "1", description, "2026-11-08", NOW, NOW)::executeUpdate)
                .isInstanceOf(PersistenceException.class)
                .rootCause().hasMessageContaining("ck_expenses_description_trimmed");
    }

    @ParameterizedTest
    @ValueSource(strings = {"a\u0001b", "a\nb", "a\u007fb", "a\u0085b", "a\u009fb"})
    void databaseRejectsControlCharactersInTheDescription(String description) {
        assertThatThrownBy(insert(ana, "1", description, "2026-11-08", NOW, NOW)::executeUpdate)
                .isInstanceOf(PersistenceException.class)
                .rootCause().hasMessageContaining("ck_expenses_description_no_control_chars");
    }

    @Test
    void databaseRejectsADescriptionOf121CodePointsAndAccepts120() {
        assertThat(insert(ana, "1", "😀".repeat(120), "2026-11-08", NOW, NOW).executeUpdate()).isEqualTo(1);
    }

    @Test
    void databaseRejectsADescriptionOf121CodePoints() {
        assertThatThrownBy(insert(ana, "1", "😀".repeat(121), "2026-11-08", NOW, NOW)::executeUpdate)
                .isInstanceOf(PersistenceException.class)
                .rootCause().hasMessageContaining("character varying(120)");
    }

    @Test
    void databaseRejectsADateBefore2000AndAcceptsTheFirstDay() {
        assertThat(insert(ana, "1", "x", "2000-01-01", NOW, NOW).executeUpdate()).isEqualTo(1);
    }

    @Test
    void databaseRejectsTheLastDayOf1999() {
        assertThatThrownBy(insert(ana, "1", "x", "1999-12-31", NOW, NOW)::executeUpdate)
                .isInstanceOf(PersistenceException.class)
                .rootCause().hasMessageContaining("ck_expenses_date_min");
    }

    @Test
    void databaseRejectsUpdatedAtBeforeCreatedAt() {
        assertThatThrownBy(insert(ana, "1", "x", "2026-11-08", NOW, NOW.minusSeconds(1))::executeUpdate)
                .isInstanceOf(PersistenceException.class)
                .rootCause().hasMessageContaining("ck_expenses_updated_after_created");
    }

    @Test
    void noActionBlocksDeletingACategoryThatHasExpenses() {
        var own = categories.saveAndFlush(Category.createOwn(ana, "Pets", NOW));
        save(ana, own, "1", "x", LocalDate.of(2026, 11, 8), NOW);

        assertThatThrownBy(() -> entityManager.getEntityManager()
                .createNativeQuery("delete from categories where id = ?1")
                .setParameter(1, own.getId()).executeUpdate())
                .isInstanceOf(PersistenceException.class)
                .rootCause().hasMessageContaining("fk_expenses_categories");
    }

    // Why NO ACTION and not RESTRICT: deleting a user cascades to its categories and its expenses in
    // one statement, and NO ACTION checks only at the end of it.
    // PT: Por que NO ACTION e não RESTRICT: apagar um usuário apaga em cascata as categorias e as
    //     despesas num só comando, e o NO ACTION só confere no fim dele.
    @Test
    void deletingAUserCascadesToItsCategoriesAndExpensesEvenWhenTheyReferenceEachOther() {
        var own = categories.saveAndFlush(Category.createOwn(ana, "Pets", NOW));
        save(ana, own, "1", "x", LocalDate.of(2026, 11, 8), NOW);

        var deleted = entityManager.getEntityManager().createNativeQuery("delete from users where id = ?1")
                .setParameter(1, ana).executeUpdate();

        assertThat(deleted).isEqualTo(1);
        assertThat(entityManager.getEntityManager()
                .createNativeQuery("select count(*) from expenses where user_id = ?1")
                .setParameter(1, ana).getSingleResult()).isEqualTo(0L);
        assertThat(entityManager.getEntityManager()
                .createNativeQuery("select count(*) from categories where user_id = ?1")
                .setParameter(1, ana).getSingleResult()).isEqualTo(0L);
    }

    private UUID persistUser(String email) {
        var user = User.register("Test", email, TestPasswordHashes.BCRYPT, "BRL", NOW);
        entityManager.persistAndFlush(user);
        return user.getId();
    }

    private Expense save(UUID userId, Category category, String amount, String description, LocalDate date,
                         Instant createdAt) {
        return expenses.saveAndFlush(Expense.create(userId, category, new BigDecimal(amount), description, date, createdAt));
    }

    private Query insert(UUID userId, String amount, String description, String date, Instant createdAt,
                         Instant updatedAt) {
        return entityManager.getEntityManager().createNativeQuery("""
                insert into expenses (id, user_id, category_id, amount, description, expense_date, created_at, updated_at)
                values (?1, ?2, ?3, cast(?4 as numeric), ?5, cast(?6 as date), ?7, ?8)
                """)
                .setParameter(1, UUID.randomUUID())
                .setParameter(2, userId)
                .setParameter(3, DefaultCategories.FOOD)
                .setParameter(4, amount)
                .setParameter(5, description)
                .setParameter(6, date)
                .setParameter(7, createdAt)
                .setParameter(8, updatedAt);
    }
}
