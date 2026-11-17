package com.yulehohenfeld.snapledger.shared.email;

/** One outgoing email, text and HTML parts; never printed with its recipient or bodies.
 *  PT: Um email de saída, partes texto e HTML; nunca impresso com o destinatário ou os corpos.
 *  Notes: docs/code-notes/email.md#emailmessage */
public record EmailMessage(String to, String subject, String text, String html) {

    // Recipient is personal data and the bodies carry account codes: neither may reach a log.
    // PT: O destinatário é dado pessoal e os corpos levam códigos de conta: nenhum pode chegar a um log.
    @Override
    public String toString() {
        return "EmailMessage[to=****, subject=" + subject + ", bodies omitted]";
    }
}
