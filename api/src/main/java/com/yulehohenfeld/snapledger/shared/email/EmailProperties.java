package com.yulehohenfeld.snapledger.shared.email;

import jakarta.validation.constraints.NotBlank;

import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.validation.annotation.Validated;

/** Sender address of every message; a blank value stops startup. PT: Endereço remetente de toda mensagem; vazio impede a subida.
 *  Notes: docs/code-notes/email.md#emailproperties */
@Validated
@ConfigurationProperties("app.mail")
public record EmailProperties(@NotBlank String from) {
}
