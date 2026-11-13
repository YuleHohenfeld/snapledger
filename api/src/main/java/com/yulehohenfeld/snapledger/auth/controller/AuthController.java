package com.yulehohenfeld.snapledger.auth.controller;

import jakarta.validation.Valid;

import lombok.RequiredArgsConstructor;

import org.springframework.http.CacheControl;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

import com.yulehohenfeld.snapledger.auth.dto.AuthResponse;
import com.yulehohenfeld.snapledger.auth.dto.LoginRequest;
import com.yulehohenfeld.snapledger.auth.dto.RefreshRequest;
import com.yulehohenfeld.snapledger.auth.dto.RegisterRequest;
import com.yulehohenfeld.snapledger.auth.dto.TokenResponse;
import com.yulehohenfeld.snapledger.auth.service.AuthService;

/**
 * The contract's public {@code /auth/*} endpoints; chain 1 never reads Authorization (ADR 0005).
 *
 * <p>PT: Os endpoints públicos {@code /auth/*} do contrato; a cadeia 1 nunca lê o Authorization
 * (ADR 0005).
 * Notes: docs/code-notes/auth.md#authcontroller
 */
@RestController
@RequestMapping("/api/v1/auth")
@RequiredArgsConstructor
public class AuthController {

    private final AuthService service;

    @PostMapping("/register")
    public ResponseEntity<AuthResponse> register(@Valid @RequestBody RegisterRequest request) {
        return withTokens(HttpStatus.CREATED).body(service.register(request));
    }

    @PostMapping("/login")
    public ResponseEntity<AuthResponse> login(@Valid @RequestBody LoginRequest request) {
        return withTokens(HttpStatus.OK).body(service.login(request));
    }

    @PostMapping("/refresh")
    public ResponseEntity<TokenResponse> refresh(@Valid @RequestBody RefreshRequest request) {
        return withTokens(HttpStatus.OK).body(service.refresh(request));
    }

    @PostMapping("/logout")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void logout(@Valid @RequestBody RefreshRequest request) {
        service.logout(request);
    }

    // A response carrying tokens must never be stored by any cache (RFC 6749 section 5.1).
    // PT: Uma resposta com tokens nunca pode ser guardada por nenhum cache (RFC 6749 seção 5.1).
    private static ResponseEntity.BodyBuilder withTokens(HttpStatus status) {
        return ResponseEntity.status(status)
                .cacheControl(CacheControl.noStore())
                .header(HttpHeaders.PRAGMA, "no-cache");
    }
}
