package com.yulehohenfeld.snapledger.auth.service;

import java.security.SecureRandom;
import java.time.Clock;
import java.time.Duration;
import java.util.Base64;
import java.util.UUID;

import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;

import com.yulehohenfeld.snapledger.accountcode.entity.CodePurpose;
import com.yulehohenfeld.snapledger.accountcode.service.AccountCodeService;
import com.yulehohenfeld.snapledger.accountcode.service.AccountCodeHasher;
import com.yulehohenfeld.snapledger.accountcode.service.AccountEmails;
import com.yulehohenfeld.snapledger.auth.dto.IssuedToken;
import com.yulehohenfeld.snapledger.auth.repository.PasswordResetGrantRepository;
import com.yulehohenfeld.snapledger.shared.email.MailDispatcher;
import com.yulehohenfeld.snapledger.shared.error.InvalidCodeException;
import com.yulehohenfeld.snapledger.shared.error.InvalidResetTokenException;
import com.yulehohenfeld.snapledger.shared.ratelimit.FixedWindowRateLimiter;
import com.yulehohenfeld.snapledger.shared.ratelimit.RateLimitKeys;
import com.yulehohenfeld.snapledger.shared.ratelimit.RateLimitProperties;
import com.yulehohenfeld.snapledger.user.service.UserService;

/**
 * Forgot password in three steps: emails a code, trades the right code for a one-use reset token
 * (verify), then sets the new password with the token (confirm) and ends every session.
 *
 * <p>PT: Esqueci a senha em três passos: envia um código por email, troca o código certo por um token
 * de redefinição de uso único (verify), e então define a senha nova com o token (confirm) e encerra
 * todas as sessões.
 * Notes: docs/code-notes/auth.md#passwordresetservice
 */
@Service
public class PasswordResetService {

    /** How long a reset token lives (contract: expiresIn 600). PT: Quanto vive um token de redefinição (contrato: expiresIn 600). */
    static final Duration RESET_TOKEN_TTL = Duration.ofMinutes(10);

    private static final int TOKEN_BYTES = 32;
    private static final SecureRandom RANDOM = new SecureRandom();
    // Fixed id for the unknown-email path: only the HMAC work matters, never the value.
    // PT: Id fixo do caminho de email desconhecido: só importa o trabalho do HMAC, nunca o valor.
    private static final UUID DUMMY_USER = new UUID(0L, 0L);

    private final UserService users;
    private final AccountCodeService codes;
    private final AccountEmails emails;
    private final MailDispatcher mail;
    private final RefreshTokenService refreshTokens;
    private final PasswordEncoder passwordEncoder;
    private final FixedWindowRateLimiter limiter;
    private final AccountCodeHasher hasher;
    private final PasswordResetGrantRepository grants;
    private final Clock clock;

    // Own instance, not the shared bean: TransactionTemplate is mutable, so its settings stay here.
    // PT: Instância própria, não o bean compartilhado: o TransactionTemplate é mutável, então as
    //     configurações dele ficam aqui.
    private final TransactionTemplate transaction;

    public PasswordResetService(UserService users, AccountCodeService codes, AccountEmails emails,
                                MailDispatcher mail, RefreshTokenService refreshTokens,
                                PasswordEncoder passwordEncoder, FixedWindowRateLimiter limiter,
                                AccountCodeHasher hasher, PasswordResetGrantRepository grants, Clock clock,
                                PlatformTransactionManager transactionManager) {
        this.users = users;
        this.codes = codes;
        this.emails = emails;
        this.mail = mail;
        this.refreshTokens = refreshTokens;
        this.passwordEncoder = passwordEncoder;
        this.limiter = limiter;
        this.hasher = hasher;
        this.grants = grants;
        this.clock = clock;
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
     * Trades the live code for a reset token and spends the code. A wrong code is committed (attempt and
     * failure budget) and {@link InvalidCodeException} is thrown only after the commit; every refusal is the same
     * exception. An unknown email still pays for an HMAC, so it costs about what a known one does.
     *
     * <p>PT: Troca o código vivo por um token de redefinição e gasta o código. Um código errado é
     * confirmado (tentativa e orçamento de falhas) e a {@link InvalidCodeException} só é lançada depois
     * do commit; toda recusa é a mesma exceção. Um email desconhecido também paga um HMAC, então custa
     * quase o mesmo que um conhecido.
     * Notes: docs/code-notes/auth.md#passwordresetservice
     */
    public IssuedToken verify(String email, String code) {
        // Same answer as an unknown email: a per-email limit must not tell which emails exist.
        // PT: Mesma resposta de um email desconhecido: um limite por email não pode dizer quais emails existem.
        if (!limiter.tryAcquire(RateLimitProperties.PASSWORD_RESET_VERIFY_EMAIL, RateLimitKeys.ofEmail(email))
                .allowed()) {
            hasher.hash(CodePurpose.PASSWORD_RESET, DUMMY_USER, code);
            throw new InvalidCodeException();
        }
        var userId = users.findIdByEmail(email).orElse(null);
        IssuedToken token = null;
        if (userId == null) {
            hasher.hash(CodePurpose.PASSWORD_RESET, DUMMY_USER, code);
        } else {
            token = transaction.execute(status -> exchange(userId, code));
        }
        if (token == null) {
            throw new InvalidCodeException();
        }
        return token;
    }

    // Returns null instead of throwing: a rollback would undo the attempt that consume just counted.
    // PT: Devolve null em vez de lançar: um rollback desfaria a tentativa que o consume acabou de contar.
    private IssuedToken exchange(UUID userId, String code) {
        if (users.lockForUpdate(userId).isEmpty() || !codes.consume(userId, CodePurpose.PASSWORD_RESET, code)) {
            return null;
        }
        var bytes = new byte[TOKEN_BYTES];
        RANDOM.nextBytes(bytes);
        var raw = Base64.getUrlEncoder().withoutPadding().encodeToString(bytes);
        var now = clock.instant();
        grants.upsert(UUID.randomUUID(), userId, RefreshTokenService.sha256(raw), now.plus(RESET_TOKEN_TTL), now);
        return new IssuedToken(raw, RESET_TOKEN_TTL);
    }

    /**
     * Sets the new password when the token is the user's live grant; every other case is
     * {@link InvalidResetTokenException}. Hashes first, always, so an unknown token costs the same as a known one.
     * Locks the user, then the grant, then (in revokeAllOf) the families: the documented order.
     *
     * <p>PT: Define a senha nova quando o token é a permissão viva do usuário; todo outro caso é
     * {@link InvalidResetTokenException}. Gera o hash primeiro, sempre, então um token desconhecido custa
     * o mesmo que um conhecido. Trava o usuário, depois a permissão, depois (no revokeAllOf) as famílias:
     * a ordem documentada.
     * Notes: docs/code-notes/auth.md#passwordresetservice
     */
    public void confirm(String resetToken, String newPassword) {
        var newHash = passwordEncoder.encode(newPassword);
        var tokenHash = RefreshTokenService.sha256(resetToken);
        // Unlocked lookup only to learn whose row to lock first; the grant is re-read under its lock below.
        // PT: Busca sem lock só para saber qual linha travar primeiro; a permissão é relida sob o lock dela abaixo.
        var userId = grants.findUserIdByTokenHash(tokenHash).orElse(null);
        var email = userId == null ? null
                : transaction.execute(status -> reset(userId, tokenHash, newHash));
        if (email == null) {
            throw new InvalidResetTokenException();
        }
        mail.sendAfterCommit(emails.passwordChanged(email));
    }

    // Returns the email on success, null otherwise (nothing to undo on a refusal).
    // PT: Devolve o email no sucesso, null no resto (não há nada a desfazer numa recusa).
    private String reset(UUID userId, String tokenHash, String newHash) {
        var credentials = users.lockForUpdate(userId).orElse(null);
        if (credentials == null) {
            return null;
        }
        var now = clock.instant();
        var grant = grants.lockByTokenHash(tokenHash).orElse(null);
        if (grant == null || !grant.isUsable(now)) {
            return null;
        }
        grant.markUsed(now);
        users.changePassword(userId, newHash);
        users.markEmailVerified(userId);
        refreshTokens.revokeAllOf(userId);
        return credentials.user().email();
    }
}
