package com.yulehohenfeld.snapledger.shared.email;

/** Port: delivers one message, throws an unchecked exception on failure; features never see SMTP.
 *  PT: Porta: entrega uma mensagem, lança exceção não verificada em caso de falha; as features nunca veem SMTP.
 *  Notes: docs/code-notes/email.md#emailsender */
public interface EmailSender {

    void send(EmailMessage message);
}
