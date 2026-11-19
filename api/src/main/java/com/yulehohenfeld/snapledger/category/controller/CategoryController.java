package com.yulehohenfeld.snapledger.category.controller;

import java.net.URI;
import java.util.List;
import java.util.UUID;

import jakarta.validation.Valid;

import lombok.RequiredArgsConstructor;

import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PatchMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import com.yulehohenfeld.snapledger.category.dto.CategoryRequest;
import com.yulehohenfeld.snapledger.category.dto.CategoryResponse;
import com.yulehohenfeld.snapledger.category.service.CategoryService;
import com.yulehohenfeld.snapledger.shared.security.CurrentUserId;

/**
 * The contract's {@code /categories}; the user always comes from the access token.
 *
 * <p>PT: O {@code /categories} do contrato; o usuário sempre vem do token de acesso.
 * Notes: docs/code-notes/category.md#categorycontroller
 */
@RestController
@RequestMapping(CategoryController.BASE)
@RequiredArgsConstructor
public class CategoryController {

    static final String BASE = "/api/v1/categories";

    private final CategoryService service;

    @GetMapping
    public List<CategoryResponse> list(@CurrentUserId UUID userId) {
        return service.list(userId);
    }

    @PostMapping
    public ResponseEntity<CategoryResponse> create(@CurrentUserId UUID userId,
                                                   @Valid @RequestBody CategoryRequest request) {
        var created = service.create(userId, request);
        return ResponseEntity.created(URI.create(BASE + "/" + created.id())).body(created);
    }

    @PatchMapping("/{id}")
    public CategoryResponse rename(@CurrentUserId UUID userId, @PathVariable UUID id,
                                   @Valid @RequestBody CategoryRequest request) {
        return service.rename(userId, id, request);
    }

    @DeleteMapping("/{id}")
    public ResponseEntity<Void> delete(@CurrentUserId UUID userId, @PathVariable UUID id) {
        service.delete(userId, id);
        return ResponseEntity.noContent().build();
    }
}
