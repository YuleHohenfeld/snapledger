package com.yulehohenfeld.snapledger.shared.error;

import org.springframework.http.HttpStatus;

/**
 * Register with an email that already has an account (409, a trade-off accepted by the contract).
 * The detail never quotes the email: the client already knows it, and a log must not.
 *
 * <p>PT: Cadastro com um email que já tem conta (409, uma concessão aceita pelo contrato). O
 * detalhe nunca cita o email: o cliente já o conhece, e um log não pode conhecê-lo.
 */
public class EmailAlreadyRegisteredException extends ApiException {

    public EmailAlreadyRegisteredException() {
        super(HttpStatus.CONFLICT, Slugs.EMAIL_ALREADY_REGISTERED, "An account with this email already exists.");
    }
}
