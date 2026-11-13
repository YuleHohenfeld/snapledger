package com.yulehohenfeld.snapledger.user.dto;

/**
 * What login needs from an account, without the entity; never leaves the server.
 *
 * <p>PT: O que o login precisa de uma conta, sem a entidade; nunca sai do servidor.
 * Notes: docs/code-notes/user.md#usercredentials
 */
public record UserCredentials(UserResponse user, String passwordHash) {

    // The hash is a secret: a record logged by mistake must not carry it.
    // PT: O hash é um segredo: um record registrado em log por engano não pode carregá-lo.
    @Override
    public String toString() {
        return "UserCredentials[user=" + user + ", passwordHash=****]";
    }
}
