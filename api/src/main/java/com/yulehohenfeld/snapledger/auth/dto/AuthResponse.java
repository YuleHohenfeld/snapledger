package com.yulehohenfeld.snapledger.auth.dto;

import com.yulehohenfeld.snapledger.user.dto.UserResponse;

/** Register and login body; default toString is safe (parts mask). PT: O toString padrão é seguro (as partes mascaram).
 *  Notes: docs/code-notes/auth.md#authresponse */
public record AuthResponse(UserResponse user, TokenResponse tokens) {
}
