package com.yulehohenfeld.snapledger.category.service;

import static com.yulehohenfeld.snapledger.support.ApiSession.json;
import static com.yulehohenfeld.snapledger.support.ApiSession.type;
import static com.yulehohenfeld.snapledger.support.LockWaits.await;
import static org.assertj.core.api.Assertions.assertThat;

import java.util.ArrayList;
import java.util.List;
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
import org.springframework.test.web.servlet.request.MockMvcRequestBuilders;

import com.yulehohenfeld.snapledger.support.ApiSession;
import com.yulehohenfeld.snapledger.support.DefaultCategories;
import com.yulehohenfeld.snapledger.support.TestJwtSecret;
import com.yulehohenfeld.snapledger.support.TestcontainersConfiguration;

/**
 * Categories end to end on a real PostgreSQL; MockMvc, never a port.
 *
 * <p>PT: Categorias de ponta a ponta num PostgreSQL real; MockMvc, nunca uma porta.
 */
@SpringBootTest
@AutoConfigureMockMvc
@Import({TestcontainersConfiguration.class, TestJwtSecret.class})
class CategoryIntegrationTest {

    static final String BASE = "/api/v1/categories";

    @Autowired
    MockMvc mvc;

    @Autowired
    JdbcTemplate jdbc;

    @Test
    void listStartsWithTheEightDefaultsAndKeysThenTheUsersOwnWithoutKeys() throws Exception {
        var ana = ApiSession.register(mvc);
        ana.post(BASE, name("Pets"));
        ApiSession.register(mvc).post(BASE, name("Secret of another user"));

        var list = json(ana.get(BASE));

        assertThat(list).hasSize(9);
        for (var i = 0; i < 8; i++) {
            assertThat(list.get(i).get("name").asString()).isEqualTo(DefaultCategories.NAMES_BY_NAME.get(i));
            assertThat(list.get(i).get("isDefault").asBoolean()).isTrue();
            assertThat(list.get(i).get("key").asString()).isEqualTo(DefaultCategories.NAMES_BY_NAME.get(i).toLowerCase());
        }
        assertThat(list.get(8).get("name").asString()).isEqualTo("Pets");
        assertThat(list.get(8).get("isDefault").asBoolean()).isFalse();
        assertThat(list.get(8).get("key").isNull()).isTrue();
    }

    @Test
    void createRenameAndDeleteAnOwnCategory() throws Exception {
        var ana = ApiSession.register(mvc);

        var created = ana.post(BASE, name("  Pets "));
        assertThat(created.getStatus()).isEqualTo(201);
        var id = json(created).get("id").asString();
        assertThat(created.getHeader(HttpHeaders.LOCATION)).isEqualTo(BASE + "/" + id);
        assertThat(json(created).get("name").asString()).isEqualTo("Pets");

        var renamed = ana.patch(BASE + "/" + id, name("Pet care"));
        assertThat(renamed.getStatus()).isEqualTo(200);
        assertThat(json(renamed).get("name").asString()).isEqualTo("Pet care");

        assertThat(ana.delete(BASE + "/" + id).getStatus()).isEqualTo(204);
        assertThat(json(ana.get(BASE))).hasSize(8);
    }

    @Test
    void anotherUsersCategoryIs404OnPatchAndDeleteAndStaysUntouched() throws Exception {
        var ana = ApiSession.register(mvc);
        var bruno = ApiSession.register(mvc);
        var id = json(ana.post(BASE, name("Pets"))).get("id").asString();

        var patch = bruno.patch(BASE + "/" + id, name("Hacked"));
        var delete = bruno.delete(BASE + "/" + id);

        assertThat(patch.getStatus()).isEqualTo(404);
        assertThat(type(patch)).isEqualTo("urn:snapledger:problem:not-found");
        assertThat(delete.getStatus()).isEqualTo(404);
        assertThat(json(ana.get(BASE)).get(8).get("name").asString()).isEqualTo("Pets");
        assertThat(bruno.patch(BASE + "/" + UUID.randomUUID(), name("X")).getStatus()).isEqualTo(404);
    }

    @Test
    void defaultsCannotBeRenamedOrDeleted() throws Exception {
        var ana = ApiSession.register(mvc);
        var path = BASE + "/" + DefaultCategories.FOOD;

        var patch = ana.patch(path, name("Mine"));
        var delete = ana.delete(path);

        assertThat(patch.getStatus()).isEqualTo(403);
        assertThat(type(patch)).isEqualTo("urn:snapledger:problem:default-category-read-only");
        assertThat(delete.getStatus()).isEqualTo(403);
        assertThat(jdbc.queryForObject("select name from categories where id = ?", String.class, DefaultCategories.FOOD))
                .isEqualTo("Food");
    }

    @Test
    void aNameInAnyCaseThatClashesWithADefaultOrAnOwnCategoryIs409WithoutEchoingIt() throws Exception {
        var ana = ApiSession.register(mvc);
        ana.post(BASE, name("Pets"));

        var againstDefault = ana.post(BASE, name("gROCERIES"));
        var againstOwn = ana.post(BASE, name("PETS"));

        assertThat(againstDefault.getStatus()).isEqualTo(409);
        assertThat(type(againstDefault)).isEqualTo("urn:snapledger:problem:category-name-taken");
        assertThat(againstDefault.getContentAsString()).doesNotContain("gROCERIES");
        assertThat(againstOwn.getStatus()).isEqualTo(409);
        assertThat(againstOwn.getContentAsString()).doesNotContain("PETS");
    }

    @Test
    void twoUsersMayHaveTheSameOwnName() throws Exception {
        assertThat(ApiSession.register(mvc).post(BASE, name("Pets")).getStatus()).isEqualTo(201);
        assertThat(ApiSession.register(mvc).post(BASE, name("Pets")).getStatus()).isEqualTo(201);
    }

    @Test
    void renameToAnotherOwnNameOrADefaultNameIs409ButChangingOnlyTheCaseIsAllowed() throws Exception {
        var ana = ApiSession.register(mvc);
        var pets = json(ana.post(BASE, name("Pets"))).get("id").asString();
        ana.post(BASE, name("Gym"));

        assertThat(ana.patch(BASE + "/" + pets, name("gym")).getStatus()).isEqualTo(409);
        assertThat(ana.patch(BASE + "/" + pets, name("Food")).getStatus()).isEqualTo(409);
        var recased = ana.patch(BASE + "/" + pets, name("PETS"));
        assertThat(recased.getStatus()).isEqualTo(200);
        assertThat(json(recased).get("name").asString()).isEqualTo("PETS");
    }

    @Test
    void deletingACategoryThatHasExpensesIs409AndKeepsIt() throws Exception {
        var ana = ApiSession.register(mvc);
        var id = json(ana.post(BASE, name("Pets"))).get("id").asString();
        assertThat(ana.post("/api/v1/expenses", expense(id)).getStatus()).isEqualTo(201);

        var delete = ana.delete(BASE + "/" + id);

        assertThat(delete.getStatus()).isEqualTo(409);
        assertThat(type(delete)).isEqualTo("urn:snapledger:problem:category-in-use");
        assertThat(json(ana.get(BASE))).hasSize(9);
    }

    @Test
    void concurrentCreatesOfTheSameNameGiveExactlyOne201AndOne409NeverA500() throws Exception {
        var ana = ApiSession.register(mvc);
        var start = new CountDownLatch(1);
        var threads = Executors.newFixedThreadPool(2);
        try {
            Callable<Integer> create = () -> {
                await(start);
                return ana.post(BASE, name("Pets")).getStatus();
            };
            var first = threads.submit(create);
            var second = threads.submit(create);
            start.countDown();

            var statuses = List.of(first.get(20, TimeUnit.SECONDS), second.get(20, TimeUnit.SECONDS));

            assertThat(statuses).containsExactlyInAnyOrder(201, 409);
            assertThat(jdbc.queryForObject("select count(*) from categories where user_id = ?", Integer.class,
                    ana.userId())).isEqualTo(1);
        } finally {
            threads.shutdownNow();
        }
    }

    @Test
    void validationErrorsAreReportedOnTheNameField() throws Exception {
        var ana = ApiSession.register(mvc);

        for (var bad : new ArrayList<>(List.of("", "   ", "a".repeat(41), "bad​name", "bad\nname"))) {
            var response = ana.post(BASE, name(bad));
            assertThat(response.getStatus()).as("name %s", bad.length()).isEqualTo(400);
            assertThat(json(response).get("errors").get(0).get("field").asString()).isEqualTo("name");
        }
    }

    @Test
    void withoutATokenTheEndpointsAre401() throws Exception {
        assertThat(mvc.perform(MockMvcRequestBuilders.get(BASE)).andReturn().getResponse().getStatus()).isEqualTo(401);
    }

    private static String name(String value) {
        return ApiSession.nameBody(value);
    }

    private static String expense(String categoryId) {
        return ApiSession.JSON.writeValueAsString(java.util.Map.of("amount", "10.00", "description", "Dog food",
                "date", java.time.LocalDate.now(java.time.ZoneOffset.UTC).toString(), "categoryId", categoryId));
    }
}
