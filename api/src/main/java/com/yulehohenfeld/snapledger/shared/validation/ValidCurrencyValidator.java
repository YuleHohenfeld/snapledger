package com.yulehohenfeld.snapledger.shared.validation;

import java.util.Currency;
import java.util.Set;
import java.util.stream.Collectors;

import jakarta.validation.ConstraintValidator;
import jakarta.validation.ConstraintValidatorContext;

/**
 * Looks the code up in a set built once from the JDK, instead of calling
 * {@code Currency.getInstance} and catching its exception for every invalid input. The set holds
 * only uppercase codes, so a lowercase code is simply not found.
 *
 * <p>PT: Procura o código em um conjunto montado uma vez a partir do JDK, em vez de chamar
 * {@code Currency.getInstance} e capturar a exceção dele a cada entrada inválida. O conjunto só tem
 * códigos em maiúsculas, então um código em minúsculas simplesmente não é encontrado.
 */
public class ValidCurrencyValidator implements ConstraintValidator<ValidCurrency, CharSequence> {

    /**
     * ISO 4217 codes the JDK knows that are not money a person pays with: precious metals, testing
     * and "no currency" codes, units of account and bond-market units, and the fund codes (indexed
     * or settlement units that sit next to a real currency of the same country). Real currencies
     * whose code starts with X (XOF, XAF, XCD, XCG, XPF) are not here. A code missing from a future
     * JDK simply never matches.
     *
     * <p>PT: Códigos ISO 4217 que o JDK conhece e que não são dinheiro com que uma pessoa paga:
     * metais preciosos, códigos de teste e de "sem moeda", unidades de conta e unidades do mercado
     * de títulos, e os códigos de fundos (unidades indexadas ou de liquidação que existem ao lado de
     * uma moeda real do mesmo país). Moedas reais cujo código começa com X (XOF, XAF, XCD, XCG, XPF)
     * não estão aqui. Um código que sumir de um JDK futuro simplesmente nunca casa.
     */
    static final Set<String> NOT_MONEY = Set.of(
            // Precious metals: gold, silver, platinum, palladium.
            // PT: Metais preciosos: ouro, prata, platina, paládio.
            "XAU", "XAG", "XPT", "XPD",
            // Testing code and "no currency involved".
            // PT: Código de teste e "nenhuma moeda envolvida".
            "XTS", "XXX",
            // Units of account: IMF special drawing rights, SUCRE, African Development Bank unit,
            // Arab Monetary Fund accounting dinar, the old French gold and UIC francs.
            // PT: Unidades de conta: direitos especiais de saque do FMI, SUCRE, unidade do Banco
            //     Africano de Desenvolvimento, dinar contábil do Fundo Monetário Árabe, os antigos
            //     francos ouro e UIC franceses.
            "XDR", "XSU", "XUA", "XAD", "XFO", "XFU",
            // European bond-market composite units.
            // PT: Unidades compostas do mercado europeu de títulos.
            "XBA", "XBB", "XBC", "XBD",
            // Fund codes: Bolivian Mvdol, WIR euro and franc, Chilean UF, Colombian UVR, Mexican
            // UDI, US dollar next-day and same-day, Uruguayan indexed units.
            // PT: Códigos de fundos: Mvdol boliviano, euro e franco WIR, UF chilena, UVR colombiana,
            //     UDI mexicana, dólar americano next-day e same-day, unidades indexadas uruguaias.
            "BOV", "CHE", "CHW", "CLF", "COU", "MXV", "USN", "USS", "UYI");

    private static final Set<String> CODES = Currency.getAvailableCurrencies().stream()
            .map(Currency::getCurrencyCode)
            .filter(code -> !NOT_MONEY.contains(code))
            .collect(Collectors.toUnmodifiableSet());

    @Override
    public boolean isValid(CharSequence value, ConstraintValidatorContext context) {
        return value == null || CODES.contains(value.toString());
    }
}
