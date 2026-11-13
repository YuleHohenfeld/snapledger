package com.yulehohenfeld.snapledger.auth.dto;

import static org.assertj.core.api.Assertions.assertThat;

import java.time.Duration;
import java.time.Instant;
import java.util.List;
import java.util.UUID;

import jakarta.validation.Validation;
import jakarta.validation.Validator;
import jakarta.validation.ValidatorFactory;

import org.junit.jupiter.api.AfterAll;
import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;

import tools.jackson.databind.json.JsonMapper;

import com.yulehohenfeld.snapledger.user.dto.UserResponse;

/**
 * The auth records: the contract's validation rules, the trimming and default applied before
 * validation, the JSON shape and masked toString. The HTTP layer (400 bodies) is tested with the
 * controllers.
 *
 * <p>PT: Os records de auth: as regras de validação do contrato, o aparo e o default aplicados antes
 * da validação, o formato JSON e o toString mascarado. A camada HTTP (corpos 400) é testada com os
 * controllers.
 */
class AuthDtoTest {

    static final String PASSWORD = "correct-horse-battery";

    static ValidatorFactory factory;
    static Validator validator;
    final JsonMapper json = JsonMapper.builder().build();

    @BeforeAll
    static void createValidator() {
        factory = Validation.buildDefaultValidatorFactory();
        validator = factory.getValidator();
    }

    @AfterAll
    static void closeFactory() {
        factory.close();
    }

    // --- RegisterRequest ---
    // PT: --- RegisterRequest (corpo do cadastro) ---

    // Jackson builds the record through the compact constructor, so the name is trimmed before
    // Bean Validation sees it, exactly as in a real request.
    // PT: O Jackson cria o record pelo construtor compacto, então o nome é aparado antes de o Bean
    //     Validation vê-lo, exatamente como numa requisição real.
    @Test
    void registerTrimsTheNameBeforeValidation() {
        var request = json.readValue("""
                {"name": "  Ana Souza\\t ", "email": "ana@example.com", "password": "%s", "currency": "USD"}
                """.formatted(PASSWORD), RegisterRequest.class);

        assertThat(request.name()).isEqualTo("Ana Souza");
        assertThat(validator.validate(request)).isEmpty();
    }

    @Test
    void registerNameOfOnlySpacesIsRejectedAfterTrimming() {
        var request = new RegisterRequest("     ", "ana@example.com", PASSWORD, "BRL");

        assertThat(request.name()).isEmpty();
        assertThat(violatedFields(request)).containsOnly("name");
    }

    // The limit applies to the trimmed name: 80 chars plus surrounding spaces is accepted.
    // PT: O limite vale para o nome aparado: 80 chars mais espaços em volta é aceito.
    @Test
    void registerNameLimitAppliesAfterTrimming() {
        assertThat(validator.validate(new RegisterRequest("  " + "a".repeat(80) + "  ", "ana@example.com", PASSWORD, null)))
                .isEmpty();
        assertThat(violatedFields(new RegisterRequest("a".repeat(81), "ana@example.com", PASSWORD, null)))
                .containsExactly("name");
    }

    // The contract counts characters: an emoji is 1, although Java stores it as 2 chars.
    // PT: O contrato conta caracteres: um emoji é 1, embora o Java o guarde como 2 chars.
    @Test
    void registerNameCountsEmojiAsOneCharacter() {
        assertThat(validator.validate(new RegisterRequest("😀".repeat(80), "ana@example.com", PASSWORD, null)))
                .isEmpty();
        assertThat(violatedFields(new RegisterRequest("😀".repeat(81), "ana@example.com", PASSWORD, null)))
                .containsExactly("name");
    }

    // NUL would reach PostgreSQL and fail there as a 500; a zero-width-only name looks empty on
    // screen. Both are a 400 on the name field, and the message never repeats the value.
    // PT: O NUL chegaria ao PostgreSQL e falharia lá como 500; um nome só de largura zero parece vazio
    //     na tela. Os dois são um 400 no campo name, e a mensagem nunca repete o valor.
    @ParameterizedTest
    @ValueSource(strings = {"Ana\u0000", "​", "​‌‍", "Ana‮Lu", "Ana\nLu"})
    void registerNameRejectsControlAndInvisibleCharacters(String name) {
        var violations = validator.validate(new RegisterRequest(name, "ana@example.com", PASSWORD, null));

        assertThat(violations).singleElement().satisfies(violation -> {
            assertThat(violation.getPropertyPath()).hasToString("name");
            assertThat(violation.getMessage()).isEqualTo("must not contain control or invisible formatting characters");
        });
    }

    // Login rejects a blank password, so register must too: otherwise "        " (8 spaces) would
    // create an account nobody can ever log in to.
    // PT: O login rejeita senha em branco, então o cadastro também precisa rejeitar: senão "        "
    //     (8 espaços) criaria uma conta em que ninguém nunca consegue entrar.
    @Test
    void registerRejectsAPasswordOfOnlySpaces() {
        assertThat(violatedFields(new RegisterRequest("Ana", "ana@example.com", " ".repeat(8), "BRL")))
                .containsExactly("password");
        assertThat(violatedFields(new LoginRequest("ana@example.com", " ".repeat(8))))
                .containsExactly("password");
    }

    // Real X-currencies are accepted; metal and testing codes are not.
    // PT: Moedas reais com X são aceitas; códigos de metal e de teste não.
    @Test
    void registerCurrencyRejectsCodesThatAreNotMoney() {
        assertThat(validator.validate(new RegisterRequest("Ana", "ana@example.com", PASSWORD, "XOF"))).isEmpty();
        assertThat(violatedFields(new RegisterRequest("Ana", "ana@example.com", PASSWORD, "XAU")))
                .containsExactly("currency");
        assertThat(violatedFields(new RegisterRequest("Ana", "ana@example.com", PASSWORD, "XTS")))
                .containsExactly("currency");
    }

    @Test
    void registerCurrencyDefaultsToBrlWhenAbsent() {
        var request = json.readValue("""
                {"name": "Ana", "email": "ana@example.com", "password": "%s"}
                """.formatted(PASSWORD), RegisterRequest.class);

        assertThat(request.currency()).isEqualTo("BRL");
        assertThat(validator.validate(request)).isEmpty();
    }

    @Test
    void registerCurrencyIsNotNormalized() {
        assertThat(violatedFields(new RegisterRequest("Ana", "ana@example.com", PASSWORD, "brl")))
                .containsExactly("currency");
    }

    // Email is rejected, never trimmed or lowercased by the request (lowercasing happens when stored).
    // PT: O email é rejeitado, nunca aparado nem posto em minúsculas pela requisição (as minúsculas
    //     acontecem ao gravar).
    @Test
    void registerEmailWithSpacesIsRejectedNotTrimmed() {
        var request = new RegisterRequest("Ana", " ana@example.com", PASSWORD, "BRL");

        assertThat(request.email()).isEqualTo(" ana@example.com");
        assertThat(violatedFields(request)).containsExactly("email");
    }

    @Test
    void registerPasswordFollowsTheByteRule() {
        assertThat(violatedFields(new RegisterRequest("Ana", "ana@example.com", "short", "BRL")))
                .containsExactly("password");
        assertThat(violatedFields(new RegisterRequest("Ana", "ana@example.com", "é".repeat(37), "BRL")))
                .containsExactly("password"); // 37 chars, 74 bytes
        // PT: 37 chars, 74 bytes
        assertThat(violatedFields(new RegisterRequest("Ana", "ana@example.com", null, "BRL")))
                .containsExactly("password");
    }

    @Test
    void registerRequiresNameEmailAndPassword() {
        assertThat(violatedFields(new RegisterRequest(null, null, null, null)))
                .containsExactlyInAnyOrder("name", "email", "password");
    }

    @Test
    void registerToStringMasksPasswordAndPersonalData() {
        var request = new RegisterRequest("Ana Souza", "ana@example.com", PASSWORD, "BRL");

        assertThat(request.toString())
                .doesNotContain(PASSWORD)
                .doesNotContain("ana@example.com")
                .doesNotContain("Ana Souza")
                .contains("password=****");
    }

    // --- LoginRequest ---
    // PT: --- LoginRequest (corpo do login) ---

    // Login never reveals the policy: a 1-byte password is a valid request (it just fails to match).
    // PT: O login nunca revela a política: uma senha de 1 byte é uma requisição válida (só não confere).
    @Test
    void loginAcceptsAShortPassword() {
        assertThat(validator.validate(new LoginRequest("ana@example.com", "x"))).isEmpty();
    }

    @Test
    void loginRejectsBlankOrOver72BytePasswords() {
        assertThat(violatedFields(new LoginRequest("ana@example.com", "   "))).containsExactly("password");
        assertThat(violatedFields(new LoginRequest("ana@example.com", "é".repeat(37)))).containsExactly("password");
    }

    @Test
    void loginUsesTheSameEmailFormatAsRegister() {
        assertThat(violatedFields(new LoginRequest("josé@example.com", PASSWORD))).containsExactly("email");
        assertThat(violatedFields(new LoginRequest(" ana@example.com", PASSWORD))).containsExactly("email");
        assertThat(violatedFields(new LoginRequest(null, PASSWORD))).containsExactly("email");
    }

    @Test
    void loginToStringMasksEmailAndPassword() {
        assertThat(new LoginRequest("ana@example.com", PASSWORD).toString())
                .doesNotContain(PASSWORD)
                .doesNotContain("ana@example.com");
    }

    // --- TokenResponse and AuthResponse ---
    // PT: --- TokenResponse e AuthResponse (respostas) ---

    @Test
    void tokenResponseHasTheContractShapeInSeconds() {
        var tokens = TokenResponse.bearer("access.jwt", Duration.ofMinutes(15), "refresh-raw", Duration.ofDays(30));

        var body = json.readTree(json.writeValueAsString(tokens));

        assertThat(body.propertyNames()).containsExactlyInAnyOrder(
                "accessToken", "tokenType", "expiresIn", "refreshToken", "refreshExpiresIn");
        assertThat(body.get("tokenType").asString()).isEqualTo("Bearer");
        assertThat(body.get("expiresIn").asLong()).isEqualTo(900);
        assertThat(body.get("refreshExpiresIn").asLong()).isEqualTo(2_592_000);
        assertThat(body.get("expiresIn").isNumber()).isTrue();
    }

    @Test
    void tokenResponseToStringMasksBothTokens() {
        var tokens = TokenResponse.bearer("access.jwt.value", Duration.ofMinutes(15),
                "refresh-raw-value", Duration.ofDays(30));

        assertThat(tokens.toString()).doesNotContain("access.jwt.value").doesNotContain("refresh-raw-value");
    }

    @Test
    void authResponseNestsUserAndTokensAndMasksThemInToString() {
        var user = new UserResponse(UUID.randomUUID(), "Ana Souza", "ana@example.com", "BRL",
                Instant.parse("2026-11-10T14:03:22Z"));
        var response = new AuthResponse(user,
                TokenResponse.bearer("access.jwt.value", Duration.ofMinutes(15), "refresh-raw-value", Duration.ofDays(30)));

        var body = json.readTree(json.writeValueAsString(response));

        assertThat(body.propertyNames()).containsExactlyInAnyOrder("user", "tokens");
        assertThat(body.get("user").get("createdAt").asString()).isEqualTo("2026-11-10T14:03:22Z");
        assertThat(response.toString())
                .doesNotContain("access.jwt.value")
                .doesNotContain("refresh-raw-value")
                .doesNotContain("ana@example.com");
    }

    private static List<String> violatedFields(Object request) {
        return validator.validate(request).stream()
                .map(violation -> violation.getPropertyPath().toString())
                .toList();
    }
}
