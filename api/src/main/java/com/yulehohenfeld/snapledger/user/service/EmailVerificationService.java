package com.yulehohenfeld.snapledger.user.service;

import java.util.UUID;

import org.springframework.stereotype.Service;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;

import com.yulehohenfeld.snapledger.accountcode.entity.CodePurpose;
import com.yulehohenfeld.snapledger.accountcode.service.AccountCodeService;
import com.yulehohenfeld.snapledger.accountcode.service.AccountEmails;
import com.yulehohenfeld.snapledger.shared.email.MailDispatcher;
import com.yulehohenfeld.snapledger.shared.error.InvalidCodeException;
import com.yulehohenfeld.snapledger.shared.error.TooManyRequestsException;
import com.yulehohenfeld.snapledger.shared.error.UnauthorizedException;
import com.yulehohenfeld.snapledger.user.dto.UserResponse;

/**
 * Proves access to the account email: sends a code to the signed-in user and checks it.
 *
 * <p>PT: Prova o acesso ao email da conta: envia um código ao usuário logado e o confere.
 * Notes: docs/code-notes/user.md#emailverificationservice
 */
@Service
public class EmailVerificationService {

    private final UserService users;
    private final AccountCodeService codes;
    private final AccountEmails emails;
    private final MailDispatcher mail;

    // Own instance, not the shared bean: TransactionTemplate is mutable, so its settings stay here.
    // PT: Instância própria, não o bean compartilhado: o TransactionTemplate é mutável, então as
    //     configurações dele ficam aqui.
    private final TransactionTemplate transaction;

    public EmailVerificationService(UserService users, AccountCodeService codes, AccountEmails emails,
                                    MailDispatcher mail, PlatformTransactionManager transactionManager) {
        this.users = users;
        this.codes = codes;
        this.emails = emails;
        this.mail = mail;
        this.transaction = new TransactionTemplate(transactionManager);
    }

    /**
     * Emails a new code; an already verified account sends nothing. A refused code (cooldown, hourly
     * quota, failure budget) is {@link TooManyRequestsException} with the resend cooldown as wait.
     *
     * <p>PT: Envia um código novo por email; uma conta já verificada não envia nada. Um código
     * recusado (cooldown, cota por hora, orçamento de falhas) é {@link TooManyRequestsException} com
     * o cooldown de reenvio como espera.
     * Notes: docs/code-notes/user.md#emailverificationservice
     */
    public void send(UUID userId) {
        var user = users.getCurrent(userId);
        if (user.emailVerified()) {
            return;
        }
        var code = codes.issue(userId, CodePurpose.EMAIL_VERIFICATION)
                .orElseThrow(() -> new TooManyRequestsException(codes.resendCooldown()));
        mail.sendAfterCommit(emails.verificationCode(user.email(), code));
    }

    /**
     * Verifies the email with the live code. A bad code is {@link InvalidCodeException}, thrown only
     * after the transaction committed, so the failed attempt stays counted. An already verified
     * account returns its profile and leaves the code alone.
     *
     * <p>PT: Verifica o email com o código vivo. Um código ruim é {@link InvalidCodeException},
     * lançada só depois do commit, para a tentativa falha continuar contada. Uma conta já verificada
     * devolve o perfil e não mexe no código.
     * Notes: docs/code-notes/user.md#emailverificationservice
     */
    public UserResponse confirm(UUID userId, String code) {
        var verified = Boolean.TRUE.equals(transaction.execute(status -> verify(userId, code)));
        if (!verified) {
            throw new InvalidCodeException();
        }
        return users.getCurrent(userId);
    }

    // Returns false instead of throwing: a rollback would undo the attempt that consume just counted.
    // PT: Devolve false em vez de lançar: um rollback desfaria a tentativa que o consume acabou de contar.
    private boolean verify(UUID userId, String code) {
        var account = users.lockForUpdate(userId).orElseThrow(UnauthorizedException::new);
        if (account.user().emailVerified()) {
            return true;
        }
        if (!codes.consume(userId, CodePurpose.EMAIL_VERIFICATION, code)) {
            return false;
        }
        users.markEmailVerified(userId);
        return true;
    }
}
