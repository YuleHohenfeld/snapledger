package com.yulehohenfeld.snapledger.shared.validation;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import java.nio.charset.StandardCharsets;
import java.util.Currency;
import java.util.Set;

import jakarta.validation.ConstraintViolation;
import jakarta.validation.Validation;
import jakarta.validation.ValidationException;
import jakarta.validation.Validator;
import jakarta.validation.ValidatorFactory;
import jakarta.validation.constraints.Size;

import org.junit.jupiter.api.AfterAll;
import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;

/**
 * The reusable constraints of shared/validation, run through a real Hibernate Validator. Every
 * rejection is also checked for not echoing the rejected value in its message.
 *
 * <p>PT: As constraints reutilizáveis de shared/validation, executadas por um Hibernate Validator
 * real. Toda rejeição também é conferida para não repetir o valor rejeitado na mensagem.
 */
class ConstraintsTest {

    static ValidatorFactory factory;
    static Validator validator;

    @BeforeAll
    static void createValidator() {
        factory = Validation.buildDefaultValidatorFactory();
        validator = factory.getValidator();
    }

    @AfterAll
    static void closeFactory() {
        factory.close();
    }

    record Password(@Utf8ByteSize(min = 8, max = 72) String value) {
    }

    record SizedPassword(@Size(max = 72) String value) {
    }

    record Money(@ValidCurrency String value) {
    }

    record Mail(@ValidEmail String value) {
    }

    record Broken(@Utf8ByteSize(min = 5, max = 1) String value) {
    }

    // --- @Size counts chars, not bytes ---
    // PT: --- O @Size conta chars, não bytes ---

    // 72 x "é" is 72 Java chars but 144 UTF-8 bytes. @Size accepts it (it counts UTF-16 chars), so
    // @Size alone would let bcrypt silently drop half the password. @Utf8ByteSize rejects it.
    // PT: 72 x "é" são 72 chars do Java mas 144 bytes UTF-8. O @Size aceita (ele conta chars UTF-16),
    //     então só o @Size deixaria o bcrypt descartar metade da senha sem avisar. O @Utf8ByteSize rejeita.
    @Test
    void sizeCountsCharsSoAMultibytePasswordOf72CharsPassesSizeButFailsTheByteLimit() {
        var password = "é".repeat(72);
        assertThat(password).hasSize(72);
        assertThat(password.getBytes(StandardCharsets.UTF_8)).hasSize(144);

        assertThat(validator.validate(new SizedPassword(password))).isEmpty();
        assertThat(validator.validate(new Password(password))).hasSize(1);
    }

    // An emoji is 2 Java chars (a surrogate pair) and 4 UTF-8 bytes: @Size sees 2, bcrypt sees 4.
    // PT: Um emoji são 2 chars do Java (um par de surrogates) e 4 bytes UTF-8: o @Size vê 2, o bcrypt vê 4.
    @Test
    void sizeCountsUtf16UnitsNotCodePointsAndNotBytes() {
        var emoji = "😀";
        assertThat(emoji.length()).isEqualTo(2);
        assertThat(emoji.codePointCount(0, emoji.length())).isEqualTo(1);
        assertThat(emoji.getBytes(StandardCharsets.UTF_8)).hasSize(4);

        var password = emoji.repeat(18) + "a"; // 37 chars, 73 bytes
        // PT: 37 chars, 73 bytes
        assertThat(validator.validate(new SizedPassword(password))).isEmpty();
        assertThat(validator.validate(new Password(password))).hasSize(1);
    }

    // --- @Utf8ByteSize ---
    // PT: --- @Utf8ByteSize (tamanho em bytes UTF-8) ---

    @Test
    void byteSizeAcceptsTheExactBounds() {
        assertThat(validator.validate(new Password("a".repeat(8)))).isEmpty();
        assertThat(validator.validate(new Password("a".repeat(72)))).isEmpty();
        assertThat(validator.validate(new Password("é".repeat(36)))).isEmpty(); // 72 bytes
        // PT: 72 bytes
        assertThat(validator.validate(new Password(null))).isEmpty();
    }

    @Test
    void byteSizeRejectsOneByteOutsideTheBoundsWithoutEchoingTheValue() {
        var tooShort = "abcdefg";
        var tooLong = "a".repeat(71) + "é"; // 71 chars of 1 byte + 1 of 2 bytes = 73 bytes
        // PT: 71 chars de 1 byte + 1 de 2 bytes = 73 bytes

        assertRejectedWithoutEcho(validator.validate(new Password(tooShort)), tooShort);
        assertRejectedWithoutEcho(validator.validate(new Password(tooLong)), tooLong);
        assertThat(validator.validate(new Password(tooLong)).iterator().next().getMessage())
                .isEqualTo("must be between 8 and 72 bytes in UTF-8");
    }

    @Test
    void byteSizeWithInvalidBoundsFailsInsteadOfValidatingNothing() {
        assertThatThrownBy(() -> validator.validate(new Broken("x"))).isInstanceOf(ValidationException.class);
    }

    // A lone surrogate has no UTF-8 form: getBytes would turn it into "?", so two different
    // passwords would become the same one. Rejected with its own message, never the value.
    // PT: Um surrogate sozinho não tem forma UTF-8: o getBytes o trocaria por "?", então duas senhas
    //     diferentes virariam a mesma. Rejeitado com mensagem própria, nunca com o valor.
    @ParameterizedTest
    @ValueSource(strings = {"pass\ud800word", "pass\udfffword", "password\udbff", "\udc00password"})
    void byteSizeRejectsUnpairedSurrogates(String password) {
        var violations = validator.validate(new Password(password));

        assertRejectedWithoutEcho(violations, password);
        assertThat(violations).singleElement()
                .extracting(ConstraintViolation::getMessage).isEqualTo("must be valid Unicode text");
    }

    @Test
    void byteSizeAcceptsAValidSurrogatePair() {
        assertThat(validator.validate(new Password("pass😀word"))).isEmpty();
    }

    // --- @CodePointLength ---
    // PT: --- @CodePointLength (tamanho em code points) ---

    record Name(@CodePointLength(min = 1, max = 80) String value) {
    }

    record BrokenName(@CodePointLength(min = 2, max = 1) String value) {
    }

    // 80 emoji are 160 Java chars: @Size(max = 80) would reject them, the contract accepts them.
    // PT: 80 emojis são 160 chars do Java: o @Size(max = 80) os rejeitaria, o contrato os aceita.
    @Test
    void codePointLengthCountsAnEmojiAsOneCharacter() {
        var name = "😀".repeat(80);
        assertThat(name).hasSize(160);

        assertThat(validator.validate(new Name(name))).isEmpty();
        assertThat(validator.validate(new Name("a".repeat(80)))).isEmpty();
        assertThat(validator.validate(new Name("a"))).isEmpty();
        assertThat(validator.validate(new Name(null))).isEmpty();
    }

    @Test
    void codePointLengthRejectsOneCharacterOutsideTheBoundsWithoutEchoingTheValue() {
        var tooLong = "😀".repeat(81);

        assertRejectedWithoutEcho(validator.validate(new Name(tooLong)), tooLong);
        assertThat(validator.validate(new Name(tooLong))).singleElement()
                .extracting(ConstraintViolation::getMessage).isEqualTo("must be between 1 and 80 characters");
        assertThat(validator.validate(new Name("a".repeat(81)))).hasSize(1);
        assertThat(validator.validate(new Name(""))).hasSize(1);
    }

    @Test
    void codePointLengthWithInvalidBoundsFailsInsteadOfValidatingNothing() {
        assertThatThrownBy(() -> validator.validate(new BrokenName("x"))).isInstanceOf(ValidationException.class);
    }

    // --- @NoControlCharacters ---
    // PT: --- @NoControlCharacters (sem caracteres invisíveis) ---

    record Label(@NoControlCharacters String value) {
    }

    @ParameterizedTest
    @ValueSource(strings = {"Ana Souza", "José Ñandú", "Zoë 😀", "王小明", "محمد", "Ana Lu"})
    void noControlCharactersAcceptsVisibleText(String value) {
        assertThat(validator.validate(new Label(value))).isEmpty();
        assertThat(validator.validate(new Label(null))).isEmpty();
    }

    // Cc (NUL, tab, newline, escape, DEL, C1), Cf (zero-width space, right-to-left override, BOM,
    // soft hyphen) and an unpaired surrogate (Cs). A zero-width-only value looks empty on screen.
    // PT: Cc (NUL, tab, quebra de linha, escape, DEL, C1), Cf (espaço de largura zero, inversão
    //     direita-para-esquerda, BOM, hífen suave) e um surrogate sozinho (Cs). Um valor só de
    //     largura zero parece vazio na tela.
    @ParameterizedTest
    @ValueSource(strings = {
            "Ana\u0000", "Ana\tLu", "Ana\nLu", "Ana\u001b[31m", "Ana\u007f", "Ana\u0085",
            "​", "​​​", "Ana‮Lu", "﻿Ana", "Ana­Lu", "Ana\ud800"
    })
    void noControlCharactersRejectsInvisibleCharactersWithoutEchoingThem(String value) {
        var violations = validator.validate(new Label(value));

        assertRejectedWithoutEcho(violations, value);
        assertThat(violations).singleElement()
                .extracting(ConstraintViolation::getMessage)
                .isEqualTo("must not contain control or invisible formatting characters");
    }

    // --- @ValidCurrency ---
    // PT: --- @ValidCurrency (código de moeda) ---

    @ParameterizedTest
    @ValueSource(strings = {"BRL", "USD", "EUR", "JPY"})
    void currencyAcceptsUppercaseIsoCodes(String code) {
        assertThat(validator.validate(new Money(code))).isEmpty();
    }

    @Test
    void currencyIsOptional() {
        assertThat(validator.validate(new Money(null))).isEmpty();
    }

    @ParameterizedTest
    @ValueSource(strings = {"brl", "Brl", "ZZZ", "BR", "BRLX", "", " BRL"})
    void currencyRejectsLowercaseUnknownAndMalformedCodesWithoutEchoingThem(String code) {
        var violations = validator.validate(new Money(code));

        assertThat(violations).hasSize(1);
        assertThat(violations.iterator().next().getMessage())
                .isEqualTo("must be an uppercase ISO 4217 currency code");
    }

    // Codes the JDK knows but nobody pays with: metals, testing, units of account, fund codes.
    // PT: Códigos que o JDK conhece mas com que ninguém paga: metais, teste, unidades de conta, fundos.
    @ParameterizedTest
    @ValueSource(strings = {
            "XAU", "XAG", "XPT", "XPD", "XTS", "XXX", "XDR", "XSU", "XUA", "XAD", "XFO", "XFU",
            "XBA", "XBB", "XBC", "XBD", "BOV", "CHE", "CHW", "CLF", "COU", "MXV", "USN", "USS", "UYI"
    })
    void currencyRejectsCodesThatAreNotMoney(String code) {
        assertThat(validator.validate(new Money(code))).hasSize(1);
    }

    // Real currencies whose code starts with X: West/Central African CFA francs, East Caribbean
    // dollar, Caribbean guilder, CFP franc.
    // PT: Moedas reais cujo código começa com X: francos CFA da África Ocidental e Central, dólar do
    //     Caribe Oriental, florim caribenho, franco CFP.
    @ParameterizedTest
    @ValueSource(strings = {"XOF", "XAF", "XCD", "XCG", "XPF"})
    void currencyAcceptsRealCurrenciesThatStartWithX(String code) {
        assertThat(validator.validate(new Money(code))).isEmpty();
    }

    // Guard for JDK upgrades: a code without minor units (-1) is a metal, a unit or a test code, never
    // cash. If a new JDK adds one, this fails and the exclusion list gets reviewed.
    // PT: Proteção para upgrades do JDK: um código sem casas decimais (-1) é um metal, uma unidade ou
    //     um código de teste, nunca dinheiro. Se um JDK novo adicionar um, isto falha e a lista de
    //     exclusão é revisada.
    @Test
    void everyJdkCodeWithoutMinorUnitsIsExcluded() {
        var withoutMinorUnits = Currency.getAvailableCurrencies().stream()
                .filter(currency -> currency.getDefaultFractionDigits() < 0)
                .map(Currency::getCurrencyCode)
                .toList();

        assertThat(withoutMinorUnits).isNotEmpty();
        assertThat(ValidCurrencyValidator.NOT_MONEY).containsAll(withoutMinorUnits);
    }

    // --- @ValidEmail ---
    // PT: --- @ValidEmail (formato de email do contrato) ---

    @ParameterizedTest
    @ValueSource(strings = {"ana@example.com", "Ana.Souza+tag@example.com.br", "a@b"})
    void emailAcceptsAsciiAddresses(String email) {
        assertThat(validator.validate(new Mail(email))).isEmpty();
    }

    @Test
    void emailAcceptsExactly254Characters() {
        var email = "a".repeat(64) + "@" + "b".repeat(63) + "." + "c".repeat(63) + "." + "d".repeat(61);
        assertThat(email).hasSize(254);

        assertThat(validator.validate(new Mail(email))).isEmpty();
    }

    // Not ASCII; leading, trailing and inner space (rejected, never trimmed); tab; newline; a quoted
    // local part with a space (valid for @Email alone); not an email; empty.
    // PT: Não ASCII; espaço no começo, no fim e no meio (rejeitado, nunca aparado); tab; quebra de
    //     linha; uma parte local entre aspas com espaço (válida só para o @Email); não é email; vazio.
    @ParameterizedTest
    @ValueSource(strings = {
            "josé@example.com",
            " ana@example.com",
            "ana@example.com ",
            "ana @example.com",
            "ana@example.com\t",
            "ana@exa\nmple.com",
            "\"a b\"@example.com",
            "not-an-email",
            ""
    })
    void emailRejectsNonAsciiWhitespaceAndMalformedAddressesAsOneViolation(String email) {
        var violations = validator.validate(new Mail(email));

        assertRejectedWithoutEcho(violations, email);
        assertThat(violations).hasSize(1);
    }

    @Test
    void emailRejects255Characters() {
        var email = "a".repeat(64) + "@" + "b".repeat(63) + "." + "c".repeat(63) + "." + "d".repeat(62);
        assertThat(email).hasSize(255);

        assertRejectedWithoutEcho(validator.validate(new Mail(email)), email);
    }

    private static void assertRejectedWithoutEcho(Set<? extends ConstraintViolation<?>> violations, String value) {
        assertThat(violations).isNotEmpty();
        violations.forEach(violation -> {
            if (!value.isBlank()) {
                assertThat(violation.getMessage()).doesNotContain(value.strip());
            }
        });
    }
}
