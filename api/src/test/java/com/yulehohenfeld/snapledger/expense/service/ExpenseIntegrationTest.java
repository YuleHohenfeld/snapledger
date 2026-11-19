package com.yulehohenfeld.snapledger.expense.service;

import static com.yulehohenfeld.snapledger.support.ApiSession.json;
import static com.yulehohenfeld.snapledger.support.ApiSession.type;
import static com.yulehohenfeld.snapledger.support.LockWaits.await;
import static org.assertj.core.api.Assertions.assertThat;

import java.time.LocalDate;
import java.time.ZoneOffset;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.Callable;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.context.annotation.Import;
import org.springframework.http.HttpHeaders;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.web.servlet.MockMvc;

import com.yulehohenfeld.snapledger.support.ApiSession;
import com.yulehohenfeld.snapledger.support.DefaultCategories;
import com.yulehohenfeld.snapledger.support.TestJwtSecret;
import com.yulehohenfeld.snapledger.support.TestcontainersConfiguration;

/**
 * Expenses end to end on a real PostgreSQL; MockMvc, never a port. Dates are relative to the real
 * UTC day, because the validator reads the application clock.
 *
 * <p>PT: Despesas de ponta a ponta num PostgreSQL real; MockMvc, nunca uma porta. As datas são
 * relativas ao dia UTC real, porque o validator lê o relógio da aplicação.
 */
@SpringBootTest
@AutoConfigureMockMvc
@Import({TestcontainersConfiguration.class, TestJwtSecret.class})
class ExpenseIntegrationTest {

    static final String BASE = "/api/v1/expenses";
    static final String CATEGORIES = "/api/v1/categories";
    static final LocalDate DAY = LocalDate.now(ZoneOffset.UTC).minusDays(1);

    @Autowired
    MockMvc mvc;

    @Autowired
    JdbcTemplate jdbc;

    @Test
    void createReadReplaceAndDeleteAnExpenseWithTheContractShape() throws Exception {
        var ana = ApiSession.register(mvc);

        var created = ana.post(BASE, body("42.9", "  Weekly groceries ", DAY, DefaultCategories.GROCERIES));
        assertThat(created.getStatus()).isEqualTo(201);
        var expense = json(created);
        var id = expense.get("id").asString();
        assertThat(created.getHeader(HttpHeaders.LOCATION)).isEqualTo(BASE + "/" + id);
        assertThat(expense.get("amount").asString()).isEqualTo("42.90");
        assertThat(expense.get("description").asString()).isEqualTo("Weekly groceries");
        assertThat(expense.get("date").asString()).isEqualTo(DAY.toString());
        assertThat(expense.get("category").get("key").asString()).isEqualTo("groceries");
        assertThat(expense.get("category").get("isDefault").asBoolean()).isTrue();
        assertThat(expense.get("createdAt").asString()).isEqualTo(expense.get("updatedAt").asString());

        assertThat(json(ana.get(BASE + "/" + id))).isEqualTo(expense);

        var replaced = ana.put(BASE + "/" + id, body("5", "Snack", DAY.minusDays(2), DefaultCategories.FOOD));
        assertThat(replaced.getStatus()).isEqualTo(200);
        assertThat(json(replaced).get("amount").asString()).isEqualTo("5.00");
        assertThat(json(replaced).get("category").get("name").asString()).isEqualTo("Food");
        assertThat(json(replaced).get("createdAt")).isEqualTo(expense.get("createdAt"));

        assertThat(ana.delete(BASE + "/" + id).getStatus()).isEqualTo(204);
        assertThat(ana.get(BASE + "/" + id).getStatus()).isEqualTo(404);
        assertThat(ana.delete(BASE + "/" + id).getStatus()).isEqualTo(404);
    }

    @Test
    void anotherUsersExpenseIs404OnGetPutAndDeleteAndStaysUntouched() throws Exception {
        var ana = ApiSession.register(mvc);
        var bruno = ApiSession.register(mvc);
        var id = json(ana.post(BASE, body("10", "Mine", DAY, DefaultCategories.FOOD))).get("id").asString();

        var get = bruno.get(BASE + "/" + id);
        var put = bruno.put(BASE + "/" + id, body("1", "Hacked", DAY, DefaultCategories.FOOD));
        var delete = bruno.delete(BASE + "/" + id);

        assertThat(get.getStatus()).isEqualTo(404);
        assertThat(type(get)).isEqualTo("urn:snapledger:problem:not-found");
        assertThat(put.getStatus()).isEqualTo(404);
        assertThat(delete.getStatus()).isEqualTo(404);
        assertThat(json(ana.get(BASE + "/" + id)).get("description").asString()).isEqualTo("Mine");
    }

    @Test
    void anotherUsersCategoryIs404OnPostAndPutAndCreatesOrChangesNothing() throws Exception {
        var ana = ApiSession.register(mvc);
        var bruno = ApiSession.register(mvc);
        var brunosCategory = UUID.fromString(json(bruno.post(CATEGORIES, ApiSession.nameBody("Gym"))).get("id").asString());
        var anasExpense = json(ana.post(BASE, body("10", "Mine", DAY, DefaultCategories.FOOD))).get("id").asString();

        var post = ana.post(BASE, body("1", "x", DAY, brunosCategory));
        var put = ana.put(BASE + "/" + anasExpense, body("1", "x", DAY, brunosCategory));
        var unknown = ana.post(BASE, body("1", "x", DAY, UUID.randomUUID()));

        assertThat(post.getStatus()).isEqualTo(404);
        assertThat(put.getStatus()).isEqualTo(404);
        assertThat(unknown.getStatus()).isEqualTo(404);
        assertThat(json(ana.get(BASE + "/" + anasExpense)).get("category").get("name").asString()).isEqualTo("Food");
        assertThat(jdbc.queryForObject("select count(*) from expenses where user_id = ?", Integer.class, ana.userId()))
                .isEqualTo(1);
    }

    @Test
    void listFiltersByMonthAndByCategoryAndRejectsAnotherUsersCategory() throws Exception {
        var ana = ApiSession.register(mvc);
        var bruno = ApiSession.register(mvc);
        var brunosCategory = json(bruno.post(CATEGORIES, ApiSession.nameBody("Gym"))).get("id").asString();
        var inFood = json(ana.post(BASE, body("1", "food", LocalDate.of(2026, 3, 31), DefaultCategories.FOOD))).get("id").asString();
        ana.post(BASE, body("2", "groceries", LocalDate.of(2026, 3, 1), DefaultCategories.GROCERIES));
        ana.post(BASE, body("3", "april", LocalDate.of(2026, 4, 1), DefaultCategories.FOOD));
        bruno.post(BASE, body("4", "bruno", LocalDate.of(2026, 3, 15), DefaultCategories.FOOD));

        var march = json(ana.get(BASE + "?month=2026-03"));
        var marchFood = json(ana.get(BASE + "?month=2026-03&categoryId=" + DefaultCategories.FOOD));
        var forbidden = ana.get(BASE + "?month=2026-03&categoryId=" + brunosCategory);

        assertThat(march).hasSize(2);
        assertThat(march.get(0).get("description").asString()).isEqualTo("food");
        assertThat(march.get(1).get("description").asString()).isEqualTo("groceries");
        assertThat(marchFood).hasSize(1);
        assertThat(marchFood.get(0).get("id").asString()).isEqualTo(inFood);
        assertThat(forbidden.getStatus()).isEqualTo(404);
        assertThat(ana.get(BASE + "?month=2026-03&categoryId=" + UUID.randomUUID()).getStatus()).isEqualTo(404);
    }

    @Test
    void anEmptyMonthIsAnEmptyList() throws Exception {
        var response = ApiSession.register(mvc).get(BASE + "?month=2026-01");

        assertThat(response.getStatus()).isEqualTo(200);
        assertThat(response.getContentAsString()).isEqualTo("[]");
    }

    @Test
    void badMonthsAndIdsAre400() throws Exception {
        var ana = ApiSession.register(mvc);

        assertThat(ana.get(BASE).getStatus()).isEqualTo(400);
        assertThat(ana.get(BASE + "?month=2026-13").getStatus()).isEqualTo(400);
        assertThat(ana.get(BASE + "?month=1999-12").getStatus()).isEqualTo(400);
        assertThat(ana.get(BASE + "?month=abc").getStatus()).isEqualTo(400);
        assertThat(ana.get(BASE + "?month=2026-03&categoryId=nope").getStatus()).isEqualTo(400);
        assertThat(ana.get(BASE + "/not-a-uuid").getStatus()).isEqualTo(400);
    }

    @Test
    void theAmountIsNeverRoundedAndBoundariesAreExact() throws Exception {
        var ana = ApiSession.register(mvc);

        assertThat(ana.post(BASE, rawBody("\"12.345\"", DAY)).getStatus()).isEqualTo(400);
        assertThat(ana.post(BASE, rawBody("\"0.00\"", DAY)).getStatus()).isEqualTo(400);
        var max = ana.post(BASE, rawBody("\"9999999999.99\"", DAY));
        assertThat(max.getStatus()).isEqualTo(201);
        assertThat(json(max).get("amount").asString()).isEqualTo("9999999999.99");
        var number = ana.post(BASE, rawBody("12.5", DAY));
        assertThat(number.getStatus()).isEqualTo(201);
        assertThat(json(number).get("amount").asString()).isEqualTo("12.50");
    }

    @Test
    void tomorrowIsAcceptedTheDayAfterAndTheYear1999Are400() throws Exception {
        var ana = ApiSession.register(mvc);
        var today = LocalDate.now(ZoneOffset.UTC);

        assertThat(ana.post(BASE, body("1", "x", today.plusDays(1), DefaultCategories.FOOD)).getStatus()).isEqualTo(201);
        assertThat(ana.post(BASE, body("1", "x", today.plusDays(2), DefaultCategories.FOOD)).getStatus()).isEqualTo(400);
        assertThat(ana.post(BASE, body("1", "x", LocalDate.of(1999, 12, 31), DefaultCategories.FOOD)).getStatus())
                .isEqualTo(400);
        assertThat(ana.post(BASE, body("1", "x", LocalDate.of(2000, 1, 1), DefaultCategories.FOOD)).getStatus())
                .isEqualTo(201);
    }

    // Whatever order the two transactions commit in, the answer is a clean 4xx, never a 500.
    // PT: Seja qual for a ordem em que as duas transações confirmam, a resposta é um 4xx limpo, nunca um 500.
    @Test
    void deletingACategoryWhileAnExpenseIsInsertedEndsIn409Or404NeverA500() throws Exception {
        var ana = ApiSession.register(mvc);
        for (var round = 0; round < 5; round++) {
            var category = json(ana.post(CATEGORIES, ApiSession.nameBody("Round " + round))).get("id").asString();
            var start = new CountDownLatch(1);
            var threads = Executors.newFixedThreadPool(2);
            try {
                Callable<Integer> insert = () -> {
                    await(start);
                    return ana.post(BASE, body("1", "race", DAY, UUID.fromString(category))).getStatus();
                };
                Callable<Integer> delete = () -> {
                    await(start);
                    return ana.delete(CATEGORIES + "/" + category).getStatus();
                };
                var inserting = threads.submit(insert);
                var deleting = threads.submit(delete);
                start.countDown();

                var inserted = inserting.get(20, TimeUnit.SECONDS);
                var deleted = deleting.get(20, TimeUnit.SECONDS);

                // Insert first: 201 then delete 409. Delete first: 204 then insert 404.
                // PT: Inserir primeiro: 201 e depois delete 409. Apagar primeiro: 204 e depois insert 404.
                assertThat(List.of(inserted, deleted)).isIn(List.of(201, 409), List.of(404, 204));
                var remaining = jdbc.queryForObject("select count(*) from expenses where category_id = ?::uuid",
                        Integer.class, category);
                assertThat(remaining).isEqualTo(inserted == 201 ? 1 : 0);
            } finally {
                threads.shutdownNow();
            }
        }
    }

    @Test
    void withoutATokenTheEndpointsAre401() throws Exception {
        assertThat(mvc.perform(org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get(BASE + "?month=2026-03"))
                .andReturn().getResponse().getStatus()).isEqualTo(401);
    }

    private static String body(String amount, String description, LocalDate date, UUID categoryId) {
        return ApiSession.JSON.writeValueAsString(Map.of("amount", amount, "description", description,
                "date", date.toString(), "categoryId", categoryId.toString()));
    }

    private static String rawBody(String amountJson, LocalDate date) {
        return "{\"amount\":" + amountJson + ",\"description\":\"x\",\"date\":\"" + date + "\",\"categoryId\":\""
                + DefaultCategories.FOOD + "\"}";
    }
}
