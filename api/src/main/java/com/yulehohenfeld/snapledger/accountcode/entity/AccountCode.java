package com.yulehohenfeld.snapledger.accountcode.entity;

import java.time.Duration;
import java.time.Instant;
import java.util.UUID;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.Table;

import lombok.AccessLevel;
import lombok.Getter;
import lombok.NoArgsConstructor;

import com.yulehohenfeld.snapledger.shared.persistence.AssignedIdEntity;

/** The single live code of a (user, purpose); only the HMAC is stored, changed only by its methods.
 *  PT: O único código vivo de um (usuário, finalidade); só o HMAC é gravado, alterado só pelos métodos.
 *  Notes: docs/code-notes/account-code.md#accountcode */
@Entity
@Table(name = "account_codes")
@Getter
@NoArgsConstructor(access = AccessLevel.PROTECTED) // JPA only
// PT: só para o JPA
public class AccountCode extends AssignedIdEntity {

    /** Length of the resend window (max sends per window). PT: Tamanho da janela de reenvio. */
    public static final Duration RESEND_WINDOW = Duration.ofHours(1);

    @Column(name = "user_id", nullable = false, updatable = false)
    private UUID userId;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false, updatable = false, length = 32)
    private CodePurpose purpose;

    @Column(name = "code_hash", nullable = false, length = 64)
    private String codeHash;

    @Column(name = "sent_at", nullable = false)
    private Instant sentAt;

    @Column(name = "expires_at", nullable = false)
    private Instant expiresAt;

    @Column(nullable = false)
    private int attempts;

    @Column(name = "used_at")
    private Instant usedAt;

    @Column(name = "window_started_at", nullable = false)
    private Instant windowStartedAt;

    @Column(name = "sends_in_window", nullable = false)
    private int sendsInWindow;

    @Column(name = "failed_window_started_at")
    private Instant failedWindowStartedAt;

    @Column(name = "failed_in_window", nullable = false)
    private int failedInWindow;

    @Column(name = "created_at", nullable = false, updatable = false)
    private Instant createdAt;

    /** True while a resend must be refused: inside the cooldown, or the window's quota is spent.
     *  PT: Verdadeiro enquanto um reenvio deve ser recusado: dentro do cooldown, ou com a cota da janela esgotada.
     *  Notes: docs/code-notes/account-code.md#resend-window */
    public boolean isThrottled(Instant now, Duration cooldown, int maxSendsPerWindow) {
        if (now.isBefore(sentAt.plus(cooldown))) {
            return true;
        }
        return now.isBefore(windowStartedAt.plus(RESEND_WINDOW)) && sendsInWindow >= maxSendsPerWindow;
    }

    /** Replaces the live code: new hash and expiry, attempts back to 0, the use mark cleared, one more send counted.
     *  PT: Substitui o código vivo: hash e validade novos, tentativas em 0, marca de uso limpa, mais um envio contado.
     *  Notes: docs/code-notes/account-code.md#accountcode */
    public void reissue(String newCodeHash, Instant now, Duration ttl) {
        if (!now.isBefore(windowStartedAt.plus(RESEND_WINDOW))) {
            windowStartedAt = now;
            sendsInWindow = 1;
        } else {
            sendsInWindow++;
        }
        codeHash = newCodeHash;
        sentAt = now;
        expiresAt = now.plus(ttl);
        attempts = 0;
        usedAt = null;
    }

    /** True when the code can still be tried: unused, not expired and below the attempt limit.
     *  PT: Verdadeiro quando o código ainda pode ser tentado: não usado, não expirado e abaixo do limite de tentativas. */
    public boolean isUsable(Instant now, int maxAttempts) {
        return usedAt == null && now.isBefore(expiresAt) && attempts < maxAttempts;
    }

    /** True while guesses are refused: the failure budget of the current window is spent. A new code does not reset it.
     *  PT: Verdadeiro enquanto os palpites são recusados: o orçamento de falhas da janela atual acabou. Um código novo não o zera.
     *  Notes: docs/code-notes/account-code.md#failure-budget */
    public boolean isFailureBudgetSpent(Instant now, Duration window, int maxFailures) {
        return failedWindowStartedAt != null && now.isBefore(failedWindowStartedAt.plus(window))
                && failedInWindow >= maxFailures;
    }

    /** Counts a wrong guess on the code and on the failure budget (a fixed window opened by the first failure).
     *  PT: Conta um palpite errado no código e no orçamento de falhas (janela fixa aberta pela primeira falha).
     *  Notes: docs/code-notes/account-code.md#failure-budget */
    public void recordFailedAttempt(Instant now, Duration window) {
        attempts++;
        if (failedWindowStartedAt == null || !now.isBefore(failedWindowStartedAt.plus(window))) {
            failedWindowStartedAt = now;
            failedInWindow = 1;
        } else {
            failedInWindow++;
        }
    }

    /** Marks the code as spent and clears the failure budget. PT: Marca o código como gasto e zera o orçamento de falhas. */
    public void consume(Instant now) {
        usedAt = now;
        failedWindowStartedAt = null;
        failedInWindow = 0;
    }

    // Id and purpose only: the hash and the user are not for logs.
    // PT: Só id e finalidade: o hash e o usuário não são para logs.
    @Override
    public String toString() {
        return "AccountCode[id=" + getId() + ", purpose=" + purpose + "]";
    }
}
