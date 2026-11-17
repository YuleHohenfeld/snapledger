package com.yulehohenfeld.snapledger.user.controller;

import java.util.UUID;

import jakarta.validation.Valid;

import lombok.RequiredArgsConstructor;

import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import com.yulehohenfeld.snapledger.shared.security.CurrentUserId;
import com.yulehohenfeld.snapledger.user.dto.EmailVerificationConfirmRequest;
import com.yulehohenfeld.snapledger.user.dto.UserResponse;
import com.yulehohenfeld.snapledger.user.service.EmailVerificationService;
import com.yulehohenfeld.snapledger.user.service.UserService;

/**
 * The contract's {@code /users/me}; the user always comes from the access token.
 *
 * <p>PT: O {@code /users/me} do contrato; o usuário sempre vem do token de acesso.
 * Notes: docs/code-notes/user.md#usercontroller
 */
@RestController
@RequestMapping("/api/v1/users")
@RequiredArgsConstructor
public class UserController {

    private final UserService service;
    private final EmailVerificationService emailVerification;

    @GetMapping("/me")
    public UserResponse me(@CurrentUserId UUID userId) {
        return service.getCurrent(userId);
    }

    @PostMapping("/me/email-verification")
    public ResponseEntity<Void> sendEmailVerification(@CurrentUserId UUID userId) {
        emailVerification.send(userId);
        return ResponseEntity.accepted().build();
    }

    @PostMapping("/me/email-verification/confirm")
    public UserResponse confirmEmailVerification(@CurrentUserId UUID userId,
                                                 @Valid @RequestBody EmailVerificationConfirmRequest request) {
        return emailVerification.confirm(userId, request.code());
    }
}
