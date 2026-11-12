package com.yulehohenfeld.snapledger.shared.security;

import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.UUID;

import com.nimbusds.jose.jwk.source.ImmutableSecret;

import lombok.RequiredArgsConstructor;

import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.core.annotation.Order;
import org.springframework.core.convert.converter.Converter;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpMethod;
import org.springframework.security.config.Customizer;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.annotation.web.configuration.EnableWebSecurity;
import org.springframework.security.config.annotation.web.configurers.AbstractHttpConfigurer;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.security.oauth2.core.DelegatingOAuth2TokenValidator;
import org.springframework.security.oauth2.core.OAuth2TokenValidator;
import org.springframework.security.oauth2.jose.jws.MacAlgorithm;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.jwt.JwtAudienceValidator;
import org.springframework.security.oauth2.jwt.JwtClaimNames;
import org.springframework.security.oauth2.jwt.JwtClaimValidator;
import org.springframework.security.oauth2.jwt.JwtDecoder;
import org.springframework.security.oauth2.jwt.JwtEncoder;
import org.springframework.security.oauth2.jwt.JwtIssuerValidator;
import org.springframework.security.oauth2.jwt.JwtTimestampValidator;
import org.springframework.security.oauth2.jwt.MappedJwtClaimSetConverter;
import org.springframework.security.oauth2.jwt.NimbusJwtDecoder;
import org.springframework.security.oauth2.jwt.NimbusJwtEncoder;
import org.springframework.security.web.SecurityFilterChain;
import org.springframework.web.cors.CorsConfiguration;
import org.springframework.web.cors.CorsConfigurationSource;
import org.springframework.web.cors.UrlBasedCorsConfigurationSource;

import com.yulehohenfeld.snapledger.shared.config.CorsProperties;

/**
 * Two filter chains (ADR 0005) on top of the JWT resource server (ADR 0004).
 * Never merge them: with a single chain the bearer token filter rejects an expired token
 * before {@code permitAll()} is evaluated, and logout/refresh stop working.
 *
 * <p>PT: Duas cadeias de filtros (ADR 0005) em cima do resource server de JWT (ADR 0004). Nunca as
 * junte: com uma cadeia só, o filtro de token recusa um token vencido antes de o permitAll()
 * ser avaliado, e o logout/refresh param de funcionar.
 */
@Configuration
@EnableWebSecurity
// Declared here as well as by @ConfigurationPropertiesScan: test slices (@WebMvcTest) that
// import this class do not run the scan, and Boot registers each record only once.
// PT: Declarado aqui e também pelo @ConfigurationPropertiesScan: as fatias de teste (@WebMvcTest)
//     que importam esta classe não fazem a varredura, e o Boot registra cada record uma única vez.
@EnableConfigurationProperties({JwtProperties.class, CorsProperties.class})
@RequiredArgsConstructor
public class SecurityConfig {

    /**
     * Same API issues and validates, so only a tiny tolerance is needed (ADR 0006).
     *
     * <p>PT: A mesma API emite e valida, então só é preciso uma tolerância mínima (ADR 0006).
     */
    static final Duration CLOCK_SKEW = Duration.ofSeconds(5);

    private final JwtProperties jwt;
    private final CorsProperties cors;
    private final Clock clock;
    private final ProblemDetailAuthenticationEntryPoint entryPoint;
    private final ProblemDetailAccessDeniedHandler accessDenied;
    private final AuthPathNotFoundHandler authPathNotFound;

    /**
     * Chain 1: public auth endpoints WITHOUT the JWT filter, so the Authorization header is ignored.
     * Unlisted paths and methods fail closed with 404 (no WWW-Authenticate: no token is ever asked for here).
     *
     * <p>PT: Cadeia 1: endpoints públicos de autenticação SEM o filtro de JWT, então o header
     * Authorization é ignorado. Caminhos e métodos não listados falham fechado com 404 (sem
     * WWW-Authenticate: aqui nunca se pede token).
     */
    @Bean
    @Order(1)
    SecurityFilterChain authEndpoints(HttpSecurity http) throws Exception {
        return common(http)
                .securityMatcher("/api/v1/auth/**")
                .authorizeHttpRequests(auth -> auth
                        .requestMatchers(HttpMethod.POST,
                                "/api/v1/auth/register", "/api/v1/auth/login",
                                "/api/v1/auth/refresh", "/api/v1/auth/logout").permitAll()
                        .anyRequest().denyAll())
                .exceptionHandling(exceptions -> exceptions
                        .authenticationEntryPoint(authPathNotFound)
                        .accessDeniedHandler(authPathNotFound))
                .build();
    }

    /**
     * Chain 2: everything else requires a valid access token.
     *
     * <p>PT: Cadeia 2: todo o resto exige um token de acesso válido.
     */
    @Bean
    @Order(2)
    SecurityFilterChain api(HttpSecurity http) throws Exception {
        return common(http)
                .authorizeHttpRequests(auth -> auth
                        .requestMatchers("/docs/**", "/v3/api-docs/**").permitAll()
                        .anyRequest().authenticated())
                .exceptionHandling(exceptions -> exceptions
                        .authenticationEntryPoint(entryPoint)
                        .accessDeniedHandler(accessDenied))
                .oauth2ResourceServer(resourceServer -> resourceServer
                        .jwt(Customizer.withDefaults())
                        .authenticationEntryPoint(entryPoint)
                        .accessDeniedHandler(accessDenied))
                .build();
    }

    /**
     * Shared by both chains: no cookies, so no session and no CSRF.
     *
     * <p>PT: Compartilhado pelas duas cadeias: sem cookies, então sem sessão e sem CSRF.
     */
    private HttpSecurity common(HttpSecurity http) throws Exception {
        return http
                .csrf(AbstractHttpConfigurer::disable)
                .cors(Customizer.withDefaults())
                .sessionManagement(session -> session.sessionCreationPolicy(SessionCreationPolicy.STATELESS));
    }

    @Bean
    JwtDecoder jwtDecoder() {
        var decoder = NimbusJwtDecoder.withSecretKey(jwt.key())
                .macAlgorithm(MacAlgorithm.HS256) // pinned: "alg: none" or any other algorithm is rejected
                // PT: fixado: "alg: none" ou qualquer outro algoritmo é recusado
                .build();
        decoder.setClaimSetConverter(keepIssuedAtAsSent());
        decoder.setJwtValidator(accessTokenValidator());
        return decoder;
    }

    /**
     * Spring's default claim converter invents {@code iat = exp - 1s} when a token has no iat,
     * which would make the required-iat check below always pass. The raw claims decide.
     * Nimbus keeps {@code "iat": null} as a present key with a null value, so presence alone is
     * not enough: a null iat counts as missing.
     *
     * <p>PT: O conversor padrão do Spring inventa iat = exp - 1s quando o token não tem iat, o que
     * faria a verificação de iat obrigatório abaixo sempre passar. As claims originais
     * decidem. O Nimbus mantém "iat": null como chave presente com valor nulo, então só
     * estar presente não basta: um iat nulo conta como ausente.
     */
    private static Converter<Map<String, Object>, Map<String, Object>> keepIssuedAtAsSent() {
        var defaults = MappedJwtClaimSetConverter.withDefaults(Map.of());
        return raw -> {
            var converted = defaults.convert(raw);
            if (raw.get(JwtClaimNames.IAT) != null || converted == null) {
                return converted;
            }
            var withoutIssuedAt = new HashMap<>(converted);
            withoutIssuedAt.remove(JwtClaimNames.IAT);
            return withoutIssuedAt;
        };
    }

    /**
     * ADR 0006: every check must pass; any failure becomes the same generic 401 in the entry point.
     * Built explicitly instead of {@code JwtValidators.createDefaultWithIssuer}, whose 60 s skew and
     * system clock are wrong here and which accepts tokens without exp, sub or aud.
     *
     * <p>PT: ADR 0006: toda verificação precisa passar; qualquer falha vira o mesmo 401 genérico.
     * Montado explicitamente em vez de JwtValidators.createDefaultWithIssuer, cuja
     * tolerância de 60 s e relógio do sistema estão errados aqui, e que aceita tokens sem
     * exp, sub ou aud.
     */
    private OAuth2TokenValidator<Jwt> accessTokenValidator() {
        var timestamps = new JwtTimestampValidator(CLOCK_SKEW);
        timestamps.setClock(clock); // same "now" as token issuing
        // PT: o mesmo "agora" da emissão do token
        return new DelegatingOAuth2TokenValidator<>(
                timestamps,
                new JwtIssuerValidator(jwt.issuer()),
                new JwtAudienceValidator(JwtProperties.AUDIENCE),
                new JwtClaimValidator<String>(JwtClaimNames.SUB, SecurityConfig::isCanonicalUuid),
                new JwtClaimValidator<Instant>(JwtClaimNames.EXP, Objects::nonNull),
                new JwtClaimValidator<Instant>(JwtClaimNames.IAT, Objects::nonNull));
    }

    /**
     * {@code UUID.fromString} also accepts non-canonical forms such as "1-2-3-4-5"; requiring the
     * round trip keeps exactly one textual form per user id, which is what @CurrentUserId parses.
     *
     * <p>PT: UUID.fromString também aceita formas não canônicas como "1-2-3-4-5"; exigir a ida e
     * volta (texto -> UUID -> texto igual) mantém uma única forma de texto por id, que é o
     * que o @CurrentUserId lê.
     */
    static boolean isCanonicalUuid(String value) {
        try {
            return UUID.fromString(value).toString().equalsIgnoreCase(value);
        } catch (IllegalArgumentException e) {
            return false;
        }
    }

    @Bean
    JwtEncoder jwtEncoder() {
        return new NimbusJwtEncoder(new ImmutableSecret<>(jwt.key()));
    }

    @Bean
    PasswordEncoder passwordEncoder() {
        return new BCryptPasswordEncoder();
    }

    /**
     * Explicit origins only (CorsProperties rejects wildcards). Bearer auth: no
     * credentials/cookies.
     *
     * <p>PT: Só origens explícitas (o CorsProperties recusa curingas). Autenticação Bearer: sem
     * credenciais/cookies.
     */
    @Bean
    CorsConfigurationSource corsConfigurationSource() {
        var config = new CorsConfiguration();
        config.setAllowedOrigins(cors.allowedOrigins());
        config.setAllowedMethods(List.of("GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"));
        config.setAllowedHeaders(List.of(HttpHeaders.AUTHORIZATION, HttpHeaders.CONTENT_TYPE));
        config.setExposedHeaders(List.of(HttpHeaders.LOCATION, HttpHeaders.WWW_AUTHENTICATE));
        config.setAllowCredentials(false);
        config.setMaxAge(Duration.ofHours(1));
        var source = new UrlBasedCorsConfigurationSource();
        source.registerCorsConfiguration("/**", config);
        return source;
    }
}
