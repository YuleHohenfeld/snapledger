package com.yulehohenfeld.snapledger.category.controller;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.jwt;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.patch;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.util.List;
import java.util.UUID;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.webmvc.test.autoconfigure.WebMvcTest;
import org.springframework.context.annotation.Import;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.request.RequestPostProcessor;

import tools.jackson.databind.json.JsonMapper;

import com.yulehohenfeld.snapledger.category.dto.CategoryRequest;
import com.yulehohenfeld.snapledger.category.dto.CategoryResponse;
import com.yulehohenfeld.snapledger.category.service.CategoryService;
import com.yulehohenfeld.snapledger.shared.config.ClockConfig;
import com.yulehohenfeld.snapledger.shared.error.CategoryInUseException;
import com.yulehohenfeld.snapledger.shared.error.CategoryNameTakenException;
import com.yulehohenfeld.snapledger.shared.error.DefaultCategoryReadOnlyException;
import com.yulehohenfeld.snapledger.shared.error.NotFoundException;
import com.yulehohenfeld.snapledger.support.ImportSecurityStack;

/**
 * The contract of {@code /categories} behind the real security chains, service mocked.
 *
 * <p>PT: O contrato de {@code /categories} atrás das cadeias de segurança reais, service simulado.
 */
@WebMvcTest(CategoryController.class)
@ImportSecurityStack
@Import(ClockConfig.class)
class CategoryControllerTest {

    static final String BASE = "/api/v1/categories";
    static final JsonMapper JSON = JsonMapper.builder().build();

    @Autowired
    MockMvc mvc;

    @MockitoBean
    CategoryService service;

    final UUID userId = UUID.randomUUID();

    @Test
    void listReturnsIsDefaultAndKeyForDefaultsAndNullKeyForOwn() throws Exception {
        var food = new CategoryResponse(UUID.randomUUID(), "Food", true, "food");
        var pets = new CategoryResponse(UUID.randomUUID(), "Pets", false, null);
        when(service.list(userId)).thenReturn(List.of(food, pets));

        var body = mvc.perform(get(BASE).with(auth()))
                .andExpect(status().isOk())
                .andExpect(content().contentType(MediaType.APPLICATION_JSON))
                .andExpect(jsonPath("$[0].id").value(food.id().toString()))
                .andExpect(jsonPath("$[0].name").value("Food"))
                .andExpect(jsonPath("$[0].isDefault").value(true))
                .andExpect(jsonPath("$[0].key").value("food"))
                .andExpect(jsonPath("$[1].isDefault").value(false))
                .andExpect(jsonPath("$[1].key").value((Object) null))
                .andReturn().getResponse().getContentAsString();

        assertThat(JSON.readTree(body).get(1).propertyNames())
                .containsExactlyInAnyOrder("id", "name", "isDefault", "key");
    }

    @Test
    void createIs201WithLocationAndTheCategory() throws Exception {
        var created = new CategoryResponse(UUID.randomUUID(), "Pets", false, null);
        when(service.create(eq(userId), any(CategoryRequest.class))).thenReturn(created);

        mvc.perform(post(BASE).with(auth()).contentType(MediaType.APPLICATION_JSON).content("{\"name\":\"  Pets \"}"))
                .andExpect(status().isCreated())
                .andExpect(header().string(HttpHeaders.LOCATION, BASE + "/" + created.id()))
                .andExpect(jsonPath("$.name").value("Pets"))
                .andExpect(jsonPath("$.isDefault").value(false));

        verify(service).create(userId, new CategoryRequest("Pets"));
    }

    @ParameterizedTest
    @ValueSource(strings = {"{}", "{\"name\":null}", "{\"name\":\"\"}", "{\"name\":\"   \"}",
            "{\"name\":\"Pe\\u0000ts\"}", "{\"name\":\"Pe\\nts\"}", "{\"name\":\"Pe\\u200bts\"}",
            "{\"name\":\"1234567890123456789012345678901234567890X\"}"})
    void createRejectsAnInvalidNameWithAValidationErrorThatNeverEchoesIt(String body) throws Exception {
        mvc.perform(post(BASE).with(auth()).contentType(MediaType.APPLICATION_JSON).content(body))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.type").value("urn:snapledger:problem:validation-error"))
                .andExpect(jsonPath("$.errors[0].field").value("name"));

        verifyNoInteractions(service);
    }

    @Test
    void createAcceptsExactly40CodePointsOfEmoji() throws Exception {
        when(service.create(eq(userId), any(CategoryRequest.class)))
                .thenReturn(new CategoryResponse(UUID.randomUUID(), "x", false, null));

        mvc.perform(post(BASE).with(auth()).contentType(MediaType.APPLICATION_JSON)
                        .content(JSON.writeValueAsString(java.util.Map.of("name", "😀".repeat(40)))))
                .andExpect(status().isCreated());
    }

    @Test
    void createWithATakenNameIs409() throws Exception {
        when(service.create(eq(userId), any(CategoryRequest.class))).thenThrow(new CategoryNameTakenException());

        mvc.perform(post(BASE).with(auth()).contentType(MediaType.APPLICATION_JSON).content("{\"name\":\"Pets\"}"))
                .andExpect(status().isConflict())
                .andExpect(content().contentTypeCompatibleWith(MediaType.APPLICATION_PROBLEM_JSON))
                .andExpect(jsonPath("$.type").value("urn:snapledger:problem:category-name-taken"))
                .andExpect(jsonPath("$.detail").value(org.hamcrest.Matchers.not(org.hamcrest.Matchers.containsString("Pets"))));
    }

    @Test
    void renameReturnsTheCategory() throws Exception {
        var id = UUID.randomUUID();
        when(service.rename(eq(userId), eq(id), any(CategoryRequest.class)))
                .thenReturn(new CategoryResponse(id, "Pet care", false, null));

        mvc.perform(patch(BASE + "/" + id).with(auth()).contentType(MediaType.APPLICATION_JSON)
                        .content("{\"name\":\"Pet care\"}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.name").value("Pet care"));
    }

    @Test
    void renameOfADefaultIs403() throws Exception {
        var id = UUID.randomUUID();
        when(service.rename(eq(userId), eq(id), any(CategoryRequest.class))).thenThrow(new DefaultCategoryReadOnlyException());

        mvc.perform(patch(BASE + "/" + id).with(auth()).contentType(MediaType.APPLICATION_JSON).content("{\"name\":\"X\"}"))
                .andExpect(status().isForbidden())
                .andExpect(jsonPath("$.type").value("urn:snapledger:problem:default-category-read-only"));
    }

    @Test
    void renameOfAnUnknownOrForeignCategoryIs404() throws Exception {
        var id = UUID.randomUUID();
        when(service.rename(eq(userId), eq(id), any(CategoryRequest.class))).thenThrow(new NotFoundException());

        mvc.perform(patch(BASE + "/" + id).with(auth()).contentType(MediaType.APPLICATION_JSON).content("{\"name\":\"X\"}"))
                .andExpect(status().isNotFound())
                .andExpect(jsonPath("$.type").value("urn:snapledger:problem:not-found"));
    }

    @Test
    void renameWithATakenNameIs409() throws Exception {
        var id = UUID.randomUUID();
        when(service.rename(eq(userId), eq(id), any(CategoryRequest.class))).thenThrow(new CategoryNameTakenException());

        mvc.perform(patch(BASE + "/" + id).with(auth()).contentType(MediaType.APPLICATION_JSON).content("{\"name\":\"X\"}"))
                .andExpect(status().isConflict())
                .andExpect(jsonPath("$.type").value("urn:snapledger:problem:category-name-taken"));
    }

    @Test
    void deleteIs204WithAnEmptyBody() throws Exception {
        var id = UUID.randomUUID();

        mvc.perform(delete(BASE + "/" + id).with(auth()))
                .andExpect(status().isNoContent())
                .andExpect(content().string(""));

        verify(service).delete(userId, id);
    }

    @Test
    void deleteOfADefaultIs403AndOfACategoryInUseIs409() throws Exception {
        var defaultId = UUID.randomUUID();
        var usedId = UUID.randomUUID();
        org.mockito.Mockito.doThrow(new DefaultCategoryReadOnlyException()).when(service).delete(userId, defaultId);
        org.mockito.Mockito.doThrow(new CategoryInUseException()).when(service).delete(userId, usedId);

        mvc.perform(delete(BASE + "/" + defaultId).with(auth())).andExpect(status().isForbidden());
        mvc.perform(delete(BASE + "/" + usedId).with(auth()))
                .andExpect(status().isConflict())
                .andExpect(jsonPath("$.type").value("urn:snapledger:problem:category-in-use"));
    }

    @Test
    void aMalformedIdIs400() throws Exception {
        mvc.perform(delete(BASE + "/not-a-uuid").with(auth()))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.type").value("urn:snapledger:problem:validation-error"));
        mvc.perform(patch(BASE + "/not-a-uuid").with(auth()).contentType(MediaType.APPLICATION_JSON).content("{\"name\":\"X\"}"))
                .andExpect(status().isBadRequest());

        verifyNoInteractions(service);
    }

    @Test
    void withoutATokenEveryEndpointIs401() throws Exception {
        var id = UUID.randomUUID();

        mvc.perform(get(BASE)).andExpect(status().isUnauthorized());
        mvc.perform(post(BASE).contentType(MediaType.APPLICATION_JSON).content("{\"name\":\"X\"}"))
                .andExpect(status().isUnauthorized());
        mvc.perform(patch(BASE + "/" + id).contentType(MediaType.APPLICATION_JSON).content("{\"name\":\"X\"}"))
                .andExpect(status().isUnauthorized());
        mvc.perform(delete(BASE + "/" + id)).andExpect(status().isUnauthorized());

        verifyNoInteractions(service);
    }

    @Test
    void theRequestToStringNeverPrintsTheName() {
        assertThat(new CategoryRequest("Secret name").toString()).doesNotContain("Secret");
    }

    private RequestPostProcessor auth() {
        return jwt().jwt(j -> j.subject(userId.toString()));
    }
}
