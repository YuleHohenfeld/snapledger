package com.yulehohenfeld.snapledger.expense.controller;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.jwt;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.math.BigDecimal;
import java.time.Clock;
import java.time.Instant;
import java.time.LocalDate;
import java.time.YearMonth;
import java.time.ZoneOffset;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.boot.webmvc.test.autoconfigure.WebMvcTest;
import org.springframework.context.annotation.Bean;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.request.RequestPostProcessor;

import tools.jackson.databind.json.JsonMapper;

import com.yulehohenfeld.snapledger.category.dto.CategoryResponse;
import com.yulehohenfeld.snapledger.expense.dto.ExpenseRequest;
import com.yulehohenfeld.snapledger.expense.dto.ExpenseResponse;
import com.yulehohenfeld.snapledger.expense.dto.ExpenseSummaryResponse;
import com.yulehohenfeld.snapledger.expense.service.ExpenseService;
import com.yulehohenfeld.snapledger.expense.service.ExpenseSummaryService;
import com.yulehohenfeld.snapledger.shared.error.NotFoundException;
import com.yulehohenfeld.snapledger.support.ImportSecurityStack;

/**
 * The contract of {@code /expenses} behind the real security chains, service mocked, "today" fixed
 * at 2026-11-12 UTC.
 *
 * <p>PT: O contrato de {@code /expenses} atrás das cadeias de segurança reais, service simulado,
 * "hoje" fixo em 2026-11-12 UTC.
 */
@WebMvcTest(ExpenseController.class)
@ImportSecurityStack
class ExpenseControllerTest {

    static final String BASE = "/api/v1/expenses";
    static final JsonMapper JSON = JsonMapper.builder().build();
    static final Instant NOW = Instant.parse("2026-11-12T23:30:00Z");

    // A fixed clock, not ClockConfig: the date rules need a known "today". PT: Relógio fixo, não ClockConfig: as regras de data precisam de um "hoje" conhecido.
    @TestConfiguration(proxyBeanMethods = false)
    static class FixedClock {
        @Bean
        Clock clock() {
            return Clock.fixed(NOW, ZoneOffset.UTC);
        }
    }

    @Autowired
    MockMvc mvc;

    @MockitoBean
    ExpenseService service;

    @MockitoBean
    ExpenseSummaryService summaries;

    final UUID userId = UUID.randomUUID();
    final UUID categoryId = UUID.randomUUID();

    @Test
    void listPassesTheMonthAndNoFilterAndReturnsTheContractShape() throws Exception {
        var response = response(UUID.randomUUID(), "42.90");
        when(service.list(userId, YearMonth.of(2026, 11), Optional.empty())).thenReturn(List.of(response));

        var body = mvc.perform(get(BASE).param("month", "2026-11").with(auth()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$[0].id").value(response.id().toString()))
                .andExpect(jsonPath("$[0].amount").value("42.90"))
                .andExpect(jsonPath("$[0].description").value("Weekly groceries"))
                .andExpect(jsonPath("$[0].date").value("2026-11-08"))
                .andExpect(jsonPath("$[0].category.name").value("Groceries"))
                .andExpect(jsonPath("$[0].category.isDefault").value(true))
                .andExpect(jsonPath("$[0].category.key").value("groceries"))
                .andExpect(jsonPath("$[0].createdAt").value("2026-11-08T21:15:00Z"))
                .andExpect(jsonPath("$[0].updatedAt").value("2026-11-08T21:15:00Z"))
                .andReturn().getResponse().getContentAsString();

        assertThat(JSON.readTree(body).get(0).propertyNames())
                .containsExactlyInAnyOrder("id", "amount", "description", "date", "category", "createdAt", "updatedAt");
        assertThat(JSON.readTree(body).get(0).get("amount").isString()).isTrue();
    }

    @Test
    void listPassesTheCategoryFilter() throws Exception {
        when(service.list(userId, YearMonth.of(2026, 11), Optional.of(categoryId))).thenReturn(List.of());

        mvc.perform(get(BASE).param("month", "2026-11").param("categoryId", categoryId.toString()).with(auth()))
                .andExpect(status().isOk())
                .andExpect(content().json("[]"));
    }

    @Test
    void listWithAnUnknownCategoryFilterIs404() throws Exception {
        when(service.list(eq(userId), any(), any())).thenThrow(new NotFoundException());

        mvc.perform(get(BASE).param("month", "2026-11").param("categoryId", categoryId.toString()).with(auth()))
                .andExpect(status().isNotFound());
    }

    @ParameterizedTest
    @ValueSource(strings = {"2026-13", "1999-12", "abc", "2026-1", "202611", "", "10000-01", "2026-11-01", "-2026-11"})
    void listRejectsABadMonthWithoutEchoingIt(String month) throws Exception {
        mvc.perform(get(BASE).param("month", month).with(auth()))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.type").value("urn:snapledger:problem:validation-error"))
                .andExpect(content().string(org.hamcrest.Matchers.not(org.hamcrest.Matchers.containsString("abc"))));

        verifyNoInteractions(service);
    }

    @Test
    void listWithoutAMonthIs400() throws Exception {
        mvc.perform(get(BASE).with(auth()))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.type").value("urn:snapledger:problem:validation-error"));

        verifyNoInteractions(service);
    }

    @Test
    void listWithAMalformedCategoryIdIs400() throws Exception {
        mvc.perform(get(BASE).param("month", "2026-11").param("categoryId", "nope").with(auth()))
                .andExpect(status().isBadRequest());

        verifyNoInteractions(service);
    }

    @ParameterizedTest
    @ValueSource(strings = {"12", "12.5", "12.50", "9999999999.99", "0.01", "0.5"})
    void createAcceptsAValidAmountString(String amount) throws Exception {
        when(service.create(eq(userId), any(ExpenseRequest.class))).thenReturn(response(UUID.randomUUID(), "12.50"));

        mvc.perform(post(BASE).with(auth()).contentType(MediaType.APPLICATION_JSON)
                        .content(body("\"" + amount + "\"", "2026-11-08")))
                .andExpect(status().isCreated());

        var captured = org.mockito.ArgumentCaptor.forClass(ExpenseRequest.class);
        verify(service).create(eq(userId), captured.capture());
        assertThat(captured.getValue().amountValue()).isEqualByComparingTo(new BigDecimal(amount));
        assertThat(captured.getValue().amountValue().scale()).isEqualTo(2);
    }

    @Test
    void createAcceptsAJsonNumberOnlyBecauseItsExactTextMatchesThePattern() throws Exception {
        when(service.create(eq(userId), any(ExpenseRequest.class))).thenReturn(response(UUID.randomUUID(), "12.50"));

        mvc.perform(post(BASE).with(auth()).contentType(MediaType.APPLICATION_JSON).content(body("12.5", "2026-11-08")))
                .andExpect(status().isCreated());

        verify(service).create(eq(userId), org.mockito.ArgumentMatchers.argThat(r -> "12.5".equals(r.amount())));
    }

    @ParameterizedTest
    @ValueSource(strings = {"1e3", "1E3", "0.0000001", "12.345", "100000000000000000000"})
    void createRejectsAJsonNumberWhoseTextDoesNotMatch(String number) throws Exception {
        mvc.perform(post(BASE).with(auth()).contentType(MediaType.APPLICATION_JSON).content(body(number, "2026-11-08")))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.type").value("urn:snapledger:problem:validation-error"));

        verifyNoInteractions(service);
    }

    @ParameterizedTest
    @ValueSource(strings = {"0", "0.00", "-1", "-0.50", "12.345", "1e3", " 12", "12 ", "10000000000.00", "12,50",
            "", "abc", "٣", "012", "1.", ".5", "+5", "12\\n"})
    void createRejectsAnInvalidAmountString(String amount) throws Exception {
        mvc.perform(post(BASE).with(auth()).contentType(MediaType.APPLICATION_JSON)
                        .content(body("\"" + amount + "\"", "2026-11-08")))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.type").value("urn:snapledger:problem:validation-error"))
                .andExpect(jsonPath("$.errors[0].field").value("amount"));

        verifyNoInteractions(service);
    }

    @Test
    void createReturnsTheAmountAsAStringWithTwoDecimalsAnd201WithLocation() throws Exception {
        var created = response(UUID.randomUUID(), "12.50");
        when(service.create(eq(userId), any(ExpenseRequest.class))).thenReturn(created);

        mvc.perform(post(BASE).with(auth()).contentType(MediaType.APPLICATION_JSON).content(body("\"12.5\"", "2026-11-08")))
                .andExpect(status().isCreated())
                .andExpect(header().string(HttpHeaders.LOCATION, BASE + "/" + created.id()))
                .andExpect(content().string(org.hamcrest.Matchers.containsString("\"amount\":\"12.50\"")));
    }

    @ParameterizedTest
    @ValueSource(strings = {"2026-11-13", "2026-11-12", "2000-01-01"})
    void createAcceptsDatesFromTheYear2000UpToTomorrow(String date) throws Exception {
        when(service.create(eq(userId), any(ExpenseRequest.class))).thenReturn(response(UUID.randomUUID(), "1.00"));

        mvc.perform(post(BASE).with(auth()).contentType(MediaType.APPLICATION_JSON).content(body("\"1\"", date)))
                .andExpect(status().isCreated());
    }

    @ParameterizedTest
    @ValueSource(strings = {"2026-11-14", "1999-12-31", "9999-12-31", "2026-02-30", "11/08/2026", "not-a-date"})
    void createRejectsDatesBeyondTomorrowBefore2000OrMalformed(String date) throws Exception {
        mvc.perform(post(BASE).with(auth()).contentType(MediaType.APPLICATION_JSON).content(body("\"1\"", date)))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.type").value("urn:snapledger:problem:validation-error"));

        verifyNoInteractions(service);
    }

    @Test
    void createRejectsMissingFieldsAndABadCategoryId() throws Exception {
        mvc.perform(post(BASE).with(auth()).contentType(MediaType.APPLICATION_JSON).content("{}"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.errors.length()").value(4));
        mvc.perform(post(BASE).with(auth()).contentType(MediaType.APPLICATION_JSON)
                        .content("{\"amount\":\"1\",\"description\":\"x\",\"date\":\"2026-11-08\",\"categoryId\":\"nope\"}"))
                .andExpect(status().isBadRequest());

        verifyNoInteractions(service);
    }

    @ParameterizedTest
    @ValueSource(strings = {"", "   ", "a\\u0000b", "a\\nb", "a\\u200bb"})
    void createRejectsABlankOrInvisibleDescription(String description) throws Exception {
        mvc.perform(post(BASE).with(auth()).contentType(MediaType.APPLICATION_JSON)
                        .content("{\"amount\":\"1\",\"description\":\"" + description
                                + "\",\"date\":\"2026-11-08\",\"categoryId\":\"" + categoryId + "\"}"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.errors[0].field").value("description"));

        verifyNoInteractions(service);
    }

    @Test
    void createTrimsTheDescriptionAndCountsCodePointsUpTo120() throws Exception {
        when(service.create(eq(userId), any(ExpenseRequest.class))).thenReturn(response(UUID.randomUUID(), "1.00"));

        mvc.perform(post(BASE).with(auth()).contentType(MediaType.APPLICATION_JSON)
                        .content("{\"amount\":\"1\",\"description\":\"  " + "😀".repeat(120)
                                + "  \",\"date\":\"2026-11-08\",\"categoryId\":\"" + categoryId + "\"}"))
                .andExpect(status().isCreated());
        mvc.perform(post(BASE).with(auth()).contentType(MediaType.APPLICATION_JSON)
                        .content("{\"amount\":\"1\",\"description\":\"" + "😀".repeat(121)
                                + "\",\"date\":\"2026-11-08\",\"categoryId\":\"" + categoryId + "\"}"))
                .andExpect(status().isBadRequest());
    }

    @Test
    void createWithAnUnknownCategoryIs404() throws Exception {
        when(service.create(eq(userId), any(ExpenseRequest.class))).thenThrow(new NotFoundException());

        mvc.perform(post(BASE).with(auth()).contentType(MediaType.APPLICATION_JSON).content(body("\"1\"", "2026-11-08")))
                .andExpect(status().isNotFound())
                .andExpect(jsonPath("$.type").value("urn:snapledger:problem:not-found"));
    }

    @Test
    void getReturnsTheExpenseAndAMalformedIdIs400() throws Exception {
        var found = response(UUID.randomUUID(), "42.90");
        when(service.get(userId, found.id())).thenReturn(found);

        mvc.perform(get(BASE + "/" + found.id()).with(auth()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.amount").value("42.90"));
        mvc.perform(get(BASE + "/not-a-uuid").with(auth()))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.type").value("urn:snapledger:problem:validation-error"));
        mvc.perform(get(BASE + "/summary").with(auth()))
                .andExpect(status().isBadRequest());
    }

    @Test
    void getOfAnUnknownOrForeignExpenseIs404() throws Exception {
        var id = UUID.randomUUID();
        when(service.get(userId, id)).thenThrow(new NotFoundException());

        mvc.perform(get(BASE + "/" + id).with(auth())).andExpect(status().isNotFound());
    }

    @Test
    void replaceIs200WithTheUpdatedExpenseAnd404WhenNotFound() throws Exception {
        var id = UUID.randomUUID();
        when(service.replace(eq(userId), eq(id), any(ExpenseRequest.class))).thenReturn(response(id, "99.99"));

        mvc.perform(put(BASE + "/" + id).with(auth()).contentType(MediaType.APPLICATION_JSON)
                        .content(body("\"99.99\"", "2026-11-08")))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.amount").value("99.99"));

        var other = UUID.randomUUID();
        when(service.replace(eq(userId), eq(other), any(ExpenseRequest.class))).thenThrow(new NotFoundException());
        mvc.perform(put(BASE + "/" + other).with(auth()).contentType(MediaType.APPLICATION_JSON)
                        .content(body("\"1\"", "2026-11-08")))
                .andExpect(status().isNotFound());
    }

    @Test
    void replaceValidatesTheBodyLikeCreate() throws Exception {
        mvc.perform(put(BASE + "/" + UUID.randomUUID()).with(auth()).contentType(MediaType.APPLICATION_JSON)
                        .content(body("\"0\"", "2026-11-08")))
                .andExpect(status().isBadRequest());

        verifyNoInteractions(service);
    }

    @Test
    void deleteIs204AndAnUnknownIdIs404() throws Exception {
        var id = UUID.randomUUID();
        mvc.perform(delete(BASE + "/" + id).with(auth())).andExpect(status().isNoContent()).andExpect(content().string(""));
        verify(service).delete(userId, id);

        var other = UUID.randomUUID();
        org.mockito.Mockito.doThrow(new NotFoundException()).when(service).delete(userId, other);
        mvc.perform(delete(BASE + "/" + other).with(auth())).andExpect(status().isNotFound());
    }

    @Test
    void summaryReturnsTheContractShapeWithMoneyAsStringsOfTwoPlaces() throws Exception {
        var summary = new ExpenseSummaryResponse("2026-11", "BRL", new BigDecimal("1234.50"), 3,
                new BigDecimal("0.00"), List.of(new ExpenseSummaryResponse.CategorySummary(categoryId, "Groceries",
                new BigDecimal("1234.50"), 3, new BigDecimal("100.00"))));
        when(summaries.summarize(userId, YearMonth.of(2026, 11))).thenReturn(summary);

        var body = mvc.perform(get(BASE + "/summary").param("month", "2026-11").with(auth()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.month").value("2026-11"))
                .andExpect(jsonPath("$.currency").value("BRL"))
                .andExpect(jsonPath("$.total").value("1234.50"))
                .andExpect(jsonPath("$.expenseCount").value(3))
                .andExpect(jsonPath("$.previousMonthTotal").value("0.00"))
                .andExpect(jsonPath("$.byCategory[0].categoryId").value(categoryId.toString()))
                .andExpect(jsonPath("$.byCategory[0].categoryName").value("Groceries"))
                .andExpect(jsonPath("$.byCategory[0].total").value("1234.50"))
                .andExpect(jsonPath("$.byCategory[0].expenseCount").value(3))
                .andExpect(jsonPath("$.byCategory[0].percentage").value("100.00"))
                .andReturn().getResponse().getContentAsString();

        var tree = JSON.readTree(body);
        assertThat(tree.get("total").isString()).isTrue();
        assertThat(tree.get("previousMonthTotal").isString()).isTrue();
        assertThat(tree.get("byCategory").get(0).get("percentage").isString()).isTrue();
        assertThat(tree.propertyNames()).containsExactlyInAnyOrder(
                "month", "currency", "total", "expenseCount", "previousMonthTotal", "byCategory");
        verifyNoInteractions(service);
    }

    @Test
    void summaryIsNotCapturedByTheIdRoute() throws Exception {
        when(summaries.summarize(userId, YearMonth.of(2026, 11)))
                .thenReturn(new ExpenseSummaryResponse("2026-11", "BRL", new BigDecimal("0.00"), 0,
                        new BigDecimal("0.00"), List.of()));

        mvc.perform(get(BASE + "/summary").param("month", "2026-11").with(auth()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.byCategory").isEmpty());

        verify(summaries).summarize(userId, YearMonth.of(2026, 11));
        verifyNoInteractions(service);
    }

    @ParameterizedTest
    @ValueSource(strings = {"2026-13", "1999-12", "abc", "2026-1", "202611", "", "10000-01"})
    void summaryRejectsABadMonthWithoutEchoingIt(String month) throws Exception {
        mvc.perform(get(BASE + "/summary").param("month", month).with(auth()))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.type").value("urn:snapledger:problem:validation-error"))
                .andExpect(content().string(org.hamcrest.Matchers.not(org.hamcrest.Matchers.containsString("abc"))));

        verifyNoInteractions(summaries);
    }

    @Test
    void summaryWithoutAMonthIs400() throws Exception {
        mvc.perform(get(BASE + "/summary").with(auth()))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.type").value("urn:snapledger:problem:validation-error"));

        verifyNoInteractions(summaries);
    }

    @Test
    void summaryWithoutATokenIs401() throws Exception {
        mvc.perform(get(BASE + "/summary").param("month", "2026-11")).andExpect(status().isUnauthorized());

        verifyNoInteractions(summaries);
    }

    @Test
    void withoutATokenEveryEndpointIs401() throws Exception {
        var id = UUID.randomUUID();

        mvc.perform(get(BASE).param("month", "2026-11")).andExpect(status().isUnauthorized());
        mvc.perform(post(BASE).contentType(MediaType.APPLICATION_JSON).content(body("\"1\"", "2026-11-08")))
                .andExpect(status().isUnauthorized());
        mvc.perform(get(BASE + "/" + id)).andExpect(status().isUnauthorized());
        mvc.perform(put(BASE + "/" + id).contentType(MediaType.APPLICATION_JSON).content(body("\"1\"", "2026-11-08")))
                .andExpect(status().isUnauthorized());
        mvc.perform(delete(BASE + "/" + id)).andExpect(status().isUnauthorized());

        verifyNoInteractions(service);
    }

    @Test
    void theRequestToStringNeverPrintsTheAmountOrTheDescription() {
        var request = new ExpenseRequest("123.45", "Secret shop", LocalDate.of(2026, 11, 8), categoryId);

        assertThat(request.toString()).doesNotContain("123.45").doesNotContain("Secret");
    }

    private String body(String amountJson, String date) {
        return "{\"amount\":" + amountJson + ",\"description\":\"Weekly groceries\",\"date\":\"" + date
                + "\",\"categoryId\":\"" + categoryId + "\"}";
    }

    private ExpenseResponse response(UUID id, String amount) {
        return new ExpenseResponse(id, new BigDecimal(amount), "Weekly groceries", LocalDate.of(2026, 11, 8),
                new CategoryResponse(categoryId, "Groceries", true, "groceries"),
                Instant.parse("2026-11-08T21:15:00Z"), Instant.parse("2026-11-08T21:15:00Z"));
    }

    private RequestPostProcessor auth() {
        return jwt().jwt(j -> j.subject(userId.toString()));
    }
}
