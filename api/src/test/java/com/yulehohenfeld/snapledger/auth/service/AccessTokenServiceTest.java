package com.yulehohenfeld.snapledger.auth.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.time.ZoneOffset;
import java.util.UUID;

import com.nimbusds.jwt.SignedJWT;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.boot.webmvc.test.autoconfigure.WebMvcTest;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Import;
import org.springframework.http.HttpHeaders;
import org.springframework.security.oauth2.jwt.JwtDecoder;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;

import com.yulehohenfeld.snapledger.shared.security.JwtProperties;
import com.yulehohenfeld.snapledger.support.ImportSecurityStack;
import com.yulehohenfeld.snapledger.support.TestJwtSecret;
import com.yulehohenfeld.snapledger.user.UserController;
import com.yulehohenfeld.snapledger.user.UserService;
import com.yulehohenfeld.snapledger.user.dto.UserResponse;

/**
 * Issuing and validating agree (ADR 0006): a token from AccessTokenService passes the application's
 * own strict JwtDecoder and opens {@code /users/me}. Fixed clock shared by issuer and decoder.
 *
 * <p>PT: Emitir e validar concordam (ADR 0006): um token do AccessTokenService passa no JwtDecoder
 * estrito da própria aplicação e abre o {@code /users/me}. Relógio fixo compartilhado por quem emite
 * e por quem valida.
 */
// A @WebMvcTest, not plain Mockito: the point is the real strict JwtDecoder of SecurityConfig.
// PT: Um @WebMvcTest, não Mockito puro: o objetivo é o JwtDecoder estrito real do SecurityConfig.
@WebMvcTest(UserController.class)
@ImportSecurityStack
@Import({AccessTokenServiceTest.FixedClock.class, AccessTokenService.class})
class AccessTokenServiceTest {

    static final Instant NOW = Instant.parse("2026-11-13T10:00:00.789Z");

    @Autowired
    AccessTokenService service;

    @Autowired
    JwtDecoder decoder;

    @Autowired
    MockMvc mvc;

    @MockitoBean
    UserService users;

    @Test
    void issuedTokenPassesTheApplicationDecoderWithEveryRequiredClaim() {
        var userId = UUID.randomUUID();

        var issued = service.issue(userId);
        var jwt = decoder.decode(issued.value());

        assertThat(jwt.getSubject()).isEqualTo(userId.toString());
        assertThat(jwt.getAudience()).containsExactly(JwtProperties.AUDIENCE);
        assertThat(jwt.getClaimAsString("iss")).isEqualTo(TestJwtSecret.ISSUER);
        // JWT times are whole seconds (RFC 7519 NumericDate).
        // PT: Os tempos de um JWT são segundos inteiros (NumericDate da RFC 7519).
        assertThat(jwt.getIssuedAt()).isEqualTo(Instant.parse("2026-11-13T10:00:00Z"));
        assertThat(jwt.getExpiresAt()).isEqualTo(Instant.parse("2026-11-13T10:15:00Z"));
        assertThat(issued.ttl()).isEqualTo(Duration.ofMinutes(15));
    }

    @Test
    void tokenIsHs256AndCarriesNoPersonalData() throws Exception {
        var token = SignedJWT.parse(service.issue(UUID.randomUUID()).value());

        assertThat(token.getHeader().getAlgorithm().getName()).isEqualTo("HS256");
        assertThat(token.getJWTClaimsSet().getClaims().keySet())
                .containsExactlyInAnyOrder("iss", "aud", "sub", "iat", "exp");
    }

    @Test
    void issuedTokenOpensUsersMe() throws Exception {
        var userId = UUID.randomUUID();
        when(users.getCurrent(userId)).thenReturn(new UserResponse(userId, "Ana", "ana@example.com", "BRL", NOW));

        mvc.perform(get("/api/v1/users/me")
                        .header(HttpHeaders.AUTHORIZATION, "Bearer " + service.issue(userId).value()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.id").value(userId.toString()));
    }

    @TestConfiguration(proxyBeanMethods = false)
    static class FixedClock {

        @Bean
        Clock clock() {
            return Clock.fixed(NOW, ZoneOffset.UTC);
        }
    }
}
