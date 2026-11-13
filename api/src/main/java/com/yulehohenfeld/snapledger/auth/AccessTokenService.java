package com.yulehohenfeld.snapledger.auth;

import java.time.Clock;
import java.util.List;
import java.util.UUID;

import lombok.RequiredArgsConstructor;

import org.springframework.security.oauth2.jose.jws.MacAlgorithm;
import org.springframework.security.oauth2.jwt.JwsHeader;
import org.springframework.security.oauth2.jwt.JwtClaimsSet;
import org.springframework.security.oauth2.jwt.JwtEncoder;
import org.springframework.security.oauth2.jwt.JwtEncoderParameters;
import org.springframework.stereotype.Service;

import com.yulehohenfeld.snapledger.shared.security.JwtProperties;

/**
 * Issues access tokens that the API's own strict decoder accepts (ADR 0006).
 *
 * <p>PT: Emite tokens de acesso que o próprio decoder estrito da API aceita (ADR 0006).
 * Notes: docs/code-notes/auth.md#accesstokenservice
 */
@Service
@RequiredArgsConstructor
public class AccessTokenService {

    private final JwtEncoder encoder;
    private final JwtProperties props;
    private final Clock clock;

    /**
     * HS256 JWT with iss, aud, sub (user id), iat and exp; no personal data.
     *
     * <p>PT: JWT HS256 com iss, aud, sub (id do usuário), iat e exp; sem dados pessoais.
     */
    public IssuedToken issue(UUID userId) {
        var now = clock.instant();
        var ttl = props.accessTokenTtl();
        var claims = JwtClaimsSet.builder()
                .issuer(props.issuer())
                .audience(List.of(JwtProperties.AUDIENCE))
                .subject(userId.toString())
                .issuedAt(now)
                .expiresAt(now.plus(ttl))
                .build();
        var header = JwsHeader.with(MacAlgorithm.HS256).build();
        return new IssuedToken(encoder.encode(JwtEncoderParameters.from(header, claims)).getTokenValue(), ttl);
    }
}
