package com.yulehohenfeld.snapledger.auth;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.when;

import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.time.ZoneOffset;
import java.util.Base64;
import java.util.UUID;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

/**
 * Generating a refresh token: entropy, encoding and what is stored. Repositories mocked.
 *
 * <p>PT: Geração de um refresh token: entropia, codificação e o que é gravado. Repositórios simulados.
 */
@ExtendWith(MockitoExtension.class)
class RefreshTokenServiceTest {

    static final Instant NOW = Instant.parse("2026-11-13T10:00:00Z");
    static final Duration TTL = Duration.ofDays(30);

    @Mock
    RefreshTokenRepository tokens;

    @Mock
    RefreshTokenFamilyRepository families;

    ArgumentCaptor<RefreshTokenFamily> savedFamily = ArgumentCaptor.forClass(RefreshTokenFamily.class);
    ArgumentCaptor<RefreshToken> savedToken = ArgumentCaptor.forClass(RefreshToken.class);

    RefreshTokenService service;

    @BeforeEach
    void setUp() {
        service = new RefreshTokenService(tokens, families, new RefreshTokenProperties(TTL),
                Clock.fixed(NOW, ZoneOffset.UTC));
    }

    @Test
    void startFamilyCreatesTheFamilyThenItsFirstToken() {
        var userId = UUID.randomUUID();

        var issued = startFamily(userId);

        var family = savedFamily.getValue();
        var token = savedToken.getValue();
        assertThat(family.getUserId()).isEqualTo(userId);
        assertThat(family.getCreatedAt()).isEqualTo(NOW);
        assertThat(token.getFamilyId()).isEqualTo(family.getId());
        assertThat(token.getCreatedAt()).isEqualTo(NOW);
        assertThat(token.getExpiresAt()).isEqualTo(NOW.plus(TTL));
        assertThat(token.getUsedAt()).isNull();
        assertThat(issued.ttl()).isEqualTo(TTL);
    }

    @Test
    void theRawTokenIs256RandomBitsInBase64UrlWithoutPadding() {
        var raw = startFamily(UUID.randomUUID()).value();

        assertThat(raw).hasSize(43).matches("^[A-Za-z0-9_-]+$");
        assertThat(Base64.getUrlDecoder().decode(raw)).hasSize(RefreshTokenService.TOKEN_BYTES).hasSize(32);
    }

    @Test
    void onlyTheHexSha256IsStoredNeverTheRawToken() {
        var raw = startFamily(UUID.randomUUID()).value();

        assertThat(savedToken.getValue().getTokenHash())
                .matches("^[0-9a-f]{64}$")
                .isEqualTo(RefreshTokenService.sha256(raw))
                .isNotEqualTo(raw);
    }

    @Test
    void sha256MatchesAKnownVector() {
        // FIPS 180-2 test vector for "abc".
        // PT: Vetor de teste do FIPS 180-2 para "abc".
        assertThat(RefreshTokenService.sha256("abc"))
                .isEqualTo("ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad");
    }

    @Test
    void everyCallIssuesADifferentToken() {
        var first = startFamily(UUID.randomUUID()).value();
        var second = startFamily(UUID.randomUUID()).value();

        assertThat(first).isNotEqualTo(second);
    }

    private IssuedToken startFamily(UUID userId) {
        when(families.save(savedFamily.capture())).thenAnswer(invocation -> invocation.getArgument(0));
        when(tokens.save(savedToken.capture())).thenAnswer(invocation -> invocation.getArgument(0));
        return service.startFamily(userId);
    }
}
