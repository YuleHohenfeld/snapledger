package com.yulehohenfeld.snapledger.expense.controller;

import java.net.URI;
import java.time.YearMonth;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import jakarta.validation.Valid;

import lombok.RequiredArgsConstructor;

import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import com.yulehohenfeld.snapledger.expense.dto.ExpenseRequest;
import com.yulehohenfeld.snapledger.expense.dto.ExpenseResponse;
import com.yulehohenfeld.snapledger.expense.dto.ExpenseSummaryResponse;
import com.yulehohenfeld.snapledger.expense.service.ExpenseService;
import com.yulehohenfeld.snapledger.expense.service.ExpenseSummaryService;
import com.yulehohenfeld.snapledger.shared.security.CurrentUserId;
import com.yulehohenfeld.snapledger.shared.validation.ValidMonth;

/**
 * The contract's {@code /expenses}; the user always comes from the access token. The literal
 * {@code /summary} wins over {@code /{id}} (a UUID), so the two never clash.
 *
 * <p>PT: O {@code /expenses} do contrato; o usuário sempre vem do token de acesso. O literal
 * {@code /summary} vence o {@code /{id}} (um UUID), então os dois nunca conflitam.
 * Notes: docs/code-notes/expense.md#expensecontroller
 */
@RestController
@RequestMapping(ExpenseController.BASE)
@RequiredArgsConstructor
public class ExpenseController {

    static final String BASE = "/api/v1/expenses";

    private final ExpenseService service;
    private final ExpenseSummaryService summaries;

    /** Declared before {@code /{id}} for readers; Spring prefers the literal path either way.
     *  PT: Declarado antes do {@code /{id}} para quem lê; o Spring prefere o caminho literal de qualquer forma. */
    @GetMapping("/summary")
    public ExpenseSummaryResponse summary(@CurrentUserId UUID userId,
                                          @RequestParam("month") @ValidMonth YearMonth month) {
        return summaries.summarize(userId, month);
    }

    @GetMapping
    public List<ExpenseResponse> list(@CurrentUserId UUID userId,
                                      @RequestParam("month") @ValidMonth YearMonth month,
                                      @RequestParam(name = "categoryId", required = false) UUID categoryId) {
        return service.list(userId, month, Optional.ofNullable(categoryId));
    }

    @PostMapping
    public ResponseEntity<ExpenseResponse> create(@CurrentUserId UUID userId,
                                                  @Valid @RequestBody ExpenseRequest request) {
        var created = service.create(userId, request);
        return ResponseEntity.created(URI.create(BASE + "/" + created.id())).body(created);
    }

    @GetMapping("/{id}")
    public ExpenseResponse get(@CurrentUserId UUID userId, @PathVariable UUID id) {
        return service.get(userId, id);
    }

    @PutMapping("/{id}")
    public ExpenseResponse replace(@CurrentUserId UUID userId, @PathVariable UUID id,
                                   @Valid @RequestBody ExpenseRequest request) {
        return service.replace(userId, id, request);
    }

    @DeleteMapping("/{id}")
    public ResponseEntity<Void> delete(@CurrentUserId UUID userId, @PathVariable UUID id) {
        service.delete(userId, id);
        return ResponseEntity.noContent().build();
    }
}
