package com.yulehohenfeld.snapledger.expense.service;

import static com.yulehohenfeld.snapledger.support.ApiSession.json;
import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.doAnswer;

import java.time.LocalDate;
import java.time.ZoneOffset;
import java.util.Map;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.context.annotation.Import;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.context.bean.override.mockito.MockitoSpyBean;
import org.springframework.test.web.servlet.MockMvc;

import com.yulehohenfeld.snapledger.category.repository.CategoryRepository;
import com.yulehohenfeld.snapledger.category.service.CategoryService;
import com.yulehohenfeld.snapledger.support.ApiSession;
import com.yulehohenfeld.snapledger.support.DefaultCategories;
import com.yulehohenfeld.snapledger.support.TestJwtSecret;
import com.yulehohenfeld.snapledger.support.TestcontainersConfiguration;

/**
 * A row deleted by another transaction between our load and our write is 404, never 500. The
 * "other transaction" is a plain JDBC delete (own connection, committed) run right after the load,
 * so the interleaving is deterministic: no threads, no sleeps.
 *
 * <p>PT: Uma linha apagada por outra transação entre o nosso load e a nossa escrita é 404, nunca
 * 500. A "outra transação" é um delete JDBC simples (conexão própria, commitado) logo após o load,
 * então o entrelaçamento é determinístico: sem threads, sem sleeps.
 * Notes: docs/code-notes/category.md#categoryservice
 */
@SpringBootTest
@AutoConfigureMockMvc
@Import({TestcontainersConfiguration.class, TestJwtSecret.class})
class DeletedMeanwhileIntegrationTest {

    @Autowired
    MockMvc mvc;

    @Autowired
    JdbcTemplate jdbc;

    @MockitoSpyBean
    CategoryService categoryService;

    @MockitoSpyBean
    CategoryRepository categories;

    @Test
    void replacingAnExpenseDeletedAfterItWasLoadedIs404() throws Exception {
        var ana = ApiSession.register(mvc);
        var day = LocalDate.now(ZoneOffset.UTC).minusDays(1);
        var body = ApiSession.JSON.writeValueAsString(Map.of("amount", "1", "description", "x",
                "date", day.toString(), "categoryId", DefaultCategories.FOOD.toString()));
        var id = json(ana.post("/api/v1/expenses", body)).get("id").asString();
        // replace() loads the expense first and then asks the category service: delete in between.
        // PT: replace() carrega a despesa e depois consulta o category service: apagamos no meio.
        doAnswer(call -> {
            var category = call.callRealMethod();
            jdbc.update("delete from expenses where id = ?::uuid", id);
            return category;
        }).when(categoryService).requireVisible(any(), any());

        assertThat(ana.put("/api/v1/expenses/" + id, body).getStatus()).isEqualTo(404);
    }

    @Test
    void renamingACategoryDeletedAfterItWasLoadedIs404() throws Exception {
        var ana = ApiSession.register(mvc);
        var id = json(ana.post("/api/v1/categories", ApiSession.nameBody("Gone"))).get("id").asString();
        // rename() loads the category, then checks the default names: delete in between (the answer stays false).
        // PT: rename() carrega a categoria e depois confere os nomes padrão: apagamos no meio (a resposta segue false).
        doAnswer(call -> {
            jdbc.update("delete from categories where id = ?::uuid", id);
            return false;
        }).when(categories).existsDefaultNamedIgnoreCase(any());

        assertThat(ana.patch("/api/v1/categories/" + id, ApiSession.nameBody("Renamed")).getStatus()).isEqualTo(404);
    }
}
