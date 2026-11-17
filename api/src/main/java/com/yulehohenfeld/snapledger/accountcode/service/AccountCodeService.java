package com.yulehohenfeld.snapledger.accountcode.service;

import java.security.SecureRandom;
import java.time.Clock;
import java.time.Duration;
import java.util.Optional;
import java.util.UUID;

import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;

import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import com.yulehohenfeld.snapledger.accountcode.config.AccountCodeProperties;
import com.yulehohenfeld.snapledger.accountcode.entity.CodePurpose;
import com.yulehohenfeld.snapledger.accountcode.repository.AccountCodeRepository;

/**
 * Issues and checks one-time codes; the caller sends the email and decides what a valid code unlocks.
 *
 * <p>PT: Emite e confere códigos de uso único; quem chama envia o email e decide o que um código válido libera.
 * Notes: docs/code-notes/account-code.md#accountcodeservice
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class AccountCodeService {

    private static final int CODE_BOUND = 1_000_000;
    private static final SecureRandom RANDOM = new SecureRandom();

    private final AccountCodeRepository codes;
    private final AccountCodeHasher hasher;
    private final AccountCodeProperties properties;
    private final Clock clock;

    /**
     * A fresh 6-digit code, or empty when the cooldown, the hourly quota or the daily failure budget refuses a new one. The
     * previous code of the (user, purpose) stops working. Join the caller's transaction and send the
     * email only after it commits.
     *
     * <p>PT: Um código novo de 6 dígitos, ou vazio quando o cooldown, a cota por hora ou o orçamento diário de falhas recusa um novo.
     * O código anterior do (usuário, finalidade) deixa de valer. Entra na transação de quem chama; o
     * email só deve ser enviado depois do commit.
     * Notes: docs/code-notes/account-code.md#issue
     */
    @Transactional
    public Optional<String> issue(UUID userId, CodePurpose purpose) {
        var now = clock.instant();
        // Lock and budget checks first: a refused request must not pay for a random code and an HMAC.
        // PT: Lock e checagens de orçamento primeiro: um pedido recusado não deve gastar um código aleatório e um HMAC.
        var existing = codes.lock(userId, purpose);
        if (existing.isPresent()) {
            var row = existing.get();
            if (row.isThrottled(now, properties.resendCooldown(), properties.maxSendsPerHour())
                    || row.isFailureBudgetSpent(now, properties.failureWindow(), properties.maxFailuresPerDay())) {
                return Optional.empty();
            }
            var code = newCode();
            row.reissue(hasher.hash(purpose, userId, code), now, properties.ttl());
            return Optional.of(code);
        }
        var code = newCode();
        // 0 = a concurrent first request won the unique row: treated as throttled, no exception.
        // PT: 0 = uma primeira requisição concorrente ganhou a linha única: tratado como limitado, sem exceção.
        int inserted = codes.insertIfAbsent(UUID.randomUUID(), userId, purpose.name(),
                hasher.hash(purpose, userId, code), now, now.plus(properties.ttl()));
        return inserted == 1 ? Optional.of(code) : Optional.empty();
    }

    /**
     * True and the code is spent when {@code raw} is the live code of the (user, purpose); false for
     * anything else, and a wrong guess counts an attempt. Never throws for a bad code, so the
     * caller's transaction commits the attempt: do not roll it back on false.
     *
     * <p>PT: Verdadeiro, e o código é gasto, quando {@code raw} é o código vivo do (usuário,
     * finalidade); falso para o resto, e um palpite errado conta uma tentativa. Nunca lança por um
     * código ruim, então a transação de quem chama confirma a tentativa: não faça rollback no false.
     * Notes: docs/code-notes/account-code.md#consume
     */
    @Transactional
    public boolean consume(UUID userId, CodePurpose purpose, String raw) {
        var now = clock.instant();
        var row = codes.lock(userId, purpose).orElse(null);
        if (row == null || row.isFailureBudgetSpent(now, properties.failureWindow(), properties.maxFailuresPerDay())
                || !row.isUsable(now, properties.maxAttempts())) {
            return false;
        }
        if (raw != null && hasher.matches(purpose, userId, raw, row.getCodeHash())) {
            row.consume(now);
            return true;
        }
        row.recordFailedAttempt(now, properties.failureWindow());
        // Only the guess that spends the budget gets here with it spent (the check above returned earlier otherwise).
        // PT: Só o palpite que esgota o orçamento chega aqui com ele esgotado (a checagem acima retornaria antes).
        if (row.isFailureBudgetSpent(now, properties.failureWindow(), properties.maxFailuresPerDay())) {
            log.warn("Account code failure budget exhausted userId={} purpose={}", userId, purpose);
        }
        return false;
    }

    /** The minimum wait between two code requests, for a {@code Retry-After}. PT: A espera mínima entre dois pedidos de código, para o {@code Retry-After}. */
    public Duration resendCooldown() {
        return properties.resendCooldown();
    }

    private static String newCode() {
        return "%06d".formatted(RANDOM.nextInt(CODE_BOUND));
    }
}
