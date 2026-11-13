package com.yulehohenfeld.snapledger.user.dto;

import java.time.Instant;
import java.util.UUID;

/** The contract's UserResponse; never add a password hash field. PT: Nunca adicione um campo de hash da senha.
 *  Notes: docs/code-notes/user.md#userresponse */
public record UserResponse(
        UUID id,
        String name,
        String email,
        String currency,
        Instant createdAt) {

    // Name and email are personal data: logs carry the id only (api/CLAUDE.md security rule 8).
    // PT: Nome e email são dados pessoais: os logs levam só o id (regra de segurança 8).
    @Override
    public String toString() {
        return "UserResponse[id=" + id + ", currency=" + currency + ", createdAt=" + createdAt + "]";
    }
}
