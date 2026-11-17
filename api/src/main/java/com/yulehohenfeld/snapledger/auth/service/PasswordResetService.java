package com.yulehohenfeld.snapledger.auth.service;

import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;

import com.yulehohenfeld.snapledger.accountcode.entity.CodePurpose;
import com.yulehohenfeld.snapledger.accountcode.service.AccountCodeService;
import com.yulehohenfeld.snapledger.accountcode.service.AccountEmails;
import com.yulehohenfeld.snapledger.shared.email.MailDispatcher;
import com.yulehohenfeld.snapledger.shared.error.InvalidCodeException;
import com.yulehohenfeld.snapledger.shared.ratelimit.FixedWindowRateLimiter;
import com.yulehohenfeld.snapledger.shared.ratelimit.RateLimitKeys;
import com.yulehohenfeld.snapledger.shared.ratelimit.RateLimitProperties;
import com.yulehohenfeld.snapledger.user.service.UserService;

/**
 * Forgot password: emails a code, then sets a new password with it and ends every session.
 *
 * <p>PT: Esqueci a senha: envia um código por email e depois define a senha nova com ele e encerra
 * todas as sessões.
 * Notes: docs/code-notes/auth.md#passwordresetservice
 */
@Service
public class PasswordResetService {

    private final UserService users;
    private final AccountCodeService codes;
    private final AccountEmails emails;
    private final MailDispatcher mail;
    private final RefreshTokenService refreshTokens;
    private final PasswordEncoder passwordEncoder;
    private final FixedWindowRateLimiter limiter;

    // Own instance, not the shared bean: TransactionTemplate is mutable, so its settings stay here.
    // PT: Instância própria, não o bean compartilhado: o TransactionTemplate é mutável, então as
    //     configurações dele ficam aqui.
    private final TransactionTemplate transaction;

    public PasswordResetService(UserService users, AccountCodeService codes, AccountEmails emails,
                                MailDispatcher mail, RefreshTokenService refreshTokens,
                                PasswordEncoder passwordEncoder, FixedWindowRateLimiter limiter,
                                PlatformTransactionManager transactionManager) {
        this.users = users;
        this.codes = codes;
        this.emails = emails;
        this.mail = mail;
        this.refreshTokens = refreshTokens;
        this.passwordEncoder = passwordEncoder;
        this.limiter = limiter;
        this.transaction = new TransactionTemplate(transactionManager);
    }

    /**
     * Always returns normally: unknown email, throttled email, spent budget and mail failure look the
     * same to the caller. No outer transaction; the code is committed before the email is sent.
     *
     * <p>PT: Sempre retorna normalmente: email desconhecido, email limitado, orçamento esgotado e
     * falha de email são iguais para quem chama. Sem transação externa; o código é confirmado antes
     * de o email ser enviado.
     * Notes: docs/code-notes/auth.md#passwordresetservice
     */
    public void request(String email) {
        if (!limiter.tryAcquire(RateLimitProperties.PASSWORD_RESET_EMAIL, RateLimitKeys.ofEmail(email)).allowed()) {
            return;
        }
        users.findIdByEmail(email)
                .flatMap(userId -> codes.issue(userId, CodePurpose.PASSWORD_RESET))
                .ifPresent(code -> mail.sendAfterCommit(emails.passwordResetCode(email, code)));
    }

    /**
     * Sets the new password when the code is the live one; every other case is
     * {@link InvalidCodeException}, thrown only after the transaction committed, so a wrong guess
     * stays counted. Hashes first, always, so an unknown email costs the same time as a known one.
     *
     * <p>PT: Define a senha nova quando o código é o vivo; todo outro caso é
     * {@link InvalidCodeException}, lançada só depois do commit da transação, para um palpite errado
     * continuar contado. Gera o hash primeiro, sempre, então um email desconhecido custa o mesmo
     * tempo que um conhecido.
     * Notes: docs/code-notes/auth.md#passwordresetservice
     */
    public void confirm(String email, String code, String newPassword) {
        var newHash = passwordEncoder.encode(newPassword);
        // Same answer as an unknown email: a per-email limit must not tell which emails exist.
        // PT: Mesma resposta de um email desconhecido: um limite por email não pode dizer quais emails existem.
        if (!limiter.tryAcquire(RateLimitProperties.PASSWORD_RESET_CONFIRM_EMAIL, RateLimitKeys.ofEmail(email))
                .allowed()) {
            throw new InvalidCodeException();
        }
        var changed = Boolean.TRUE.equals(transaction.execute(status -> reset(email, code, newHash)));
        if (!changed) {
            throw new InvalidCodeException();
        }
        mail.sendAfterCommit(emails.passwordChanged(email));
    }

    // Returns false instead of throwing: a rollback would undo the attempt that consume just counted.
    // PT: Devolve false em vez de lançar: um rollback desfaria a tentativa que o consume acabou de contar.
    private boolean reset(String email, String code, String newHash) {
        var userId = users.findIdByEmail(email).orElse(null);
        if (userId == null || users.lockForUpdate(userId).isEmpty()) {
            return false;
        }
        if (!codes.consume(userId, CodePurpose.PASSWORD_RESET, code)) {
            return false;
        }
        users.changePassword(userId, newHash);
        users.markEmailVerified(userId);
        refreshTokens.revokeAllOf(userId);
        return true;
    }
}
