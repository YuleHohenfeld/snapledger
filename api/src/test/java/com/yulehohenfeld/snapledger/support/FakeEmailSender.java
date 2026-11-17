package com.yulehohenfeld.snapledger.support;

import java.util.List;
import java.util.Optional;
import java.util.concurrent.CopyOnWriteArrayList;
import java.util.regex.Pattern;

import com.yulehohenfeld.snapledger.shared.email.EmailMessage;
import com.yulehohenfeld.snapledger.shared.email.EmailSender;

/**
 * An {@link EmailSender} that keeps what it was asked to send, so integration tests read the code
 * a user would have received. Not a bean by itself: tests register it where they need it.
 *
 * <p>PT: Um {@link EmailSender} que guarda o que lhe pediram para enviar, para os testes de
 * integração lerem o código que o usuário receberia. Não é um bean sozinho: os testes o registram
 * onde precisam.
 */
public class FakeEmailSender implements EmailSender {

    private static final Pattern SIX_DIGITS = Pattern.compile("\\b(\\d{6})\\b");

    private final List<EmailMessage> sent = new CopyOnWriteArrayList<>();

    @Override
    public void send(EmailMessage message) {
        sent.add(message);
    }

    public List<EmailMessage> sent() {
        return List.copyOf(sent);
    }

    public void clear() {
        sent.clear();
    }

    /** The 6-digit code of the latest message to {@code email}, if any. PT: O código de 6 dígitos da última mensagem para {@code email}. */
    public Optional<String> lastCodeFor(String email) {
        for (int i = sent.size() - 1; i >= 0; i--) {
            var message = sent.get(i);
            if (message.to().equals(email)) {
                var matcher = SIX_DIGITS.matcher(message.text());
                if (matcher.find()) {
                    return Optional.of(matcher.group(1));
                }
            }
        }
        return Optional.empty();
    }
}
