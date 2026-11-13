package com.yulehohenfeld.snapledger.support;

import static com.yulehohenfeld.snapledger.support.TestTokenHashes.hashOf;

import java.sql.Timestamp;
import java.time.Duration;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;
import java.util.concurrent.ExecutorService;

import org.springframework.jdbc.core.JdbcTemplate;

/**
 * Refresh token rows for integration tests that commit for real: unique emails to clean up, an
 * expired token and plain JDBC reads, so no test reads through the code under test.
 *
 * <p>PT: Linhas de refresh token para testes de integração que fazem commit de verdade: emails únicos
 * para limpar, um token vencido e leituras em JDBC puro, para que nenhum teste leia pelo código
 * testado.
 */
public final class RefreshTokenFixtures {

    private final JdbcTemplate jdbc;
    private final List<String> emails = new ArrayList<>();

    public RefreshTokenFixtures(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    /**
     * A new email, remembered so {@link #cleanUp} deletes its user.
     *
     * <p>PT: Um email novo, guardado para que o {@link #cleanUp} apague o usuário dele.
     */
    public String uniqueEmail() {
        var email = "user-" + UUID.randomUUID() + "@example.com";
        emails.add(email);
        return email;
    }

    /**
     * Native insert of a token that expired a day ago: the application never issues one.
     *
     * <p>PT: Insert nativo de um token que venceu há um dia: a aplicação nunca emite um assim.
     */
    public String insertExpiredToken(UUID family) {
        var raw = "expired-" + UUID.randomUUID();
        var now = Instant.now();
        jdbc.update("""
                insert into refresh_tokens (id, family_id, token_hash, expires_at, created_at)
                values (?, ?, ?, ?, ?)
                """, UUID.randomUUID(), family, hashOf(raw),
                Timestamp.from(now.minus(Duration.ofDays(1))), Timestamp.from(now.minus(Duration.ofDays(31))));
        return raw;
    }

    public UUID familyOf(String raw) {
        return jdbc.queryForObject("select family_id from refresh_tokens where token_hash = ?", UUID.class, hashOf(raw));
    }

    public Timestamp revokedAt(UUID family) {
        return jdbc.queryForObject("select revoked_at from refresh_token_families where id = ?", Timestamp.class, family);
    }

    /**
     * Stops the test's threads first, so none still writes, then deletes each user; the cascade
     * removes its families and their tokens.
     *
     * <p>PT: Para as threads do teste primeiro, para que nenhuma ainda grave, e depois apaga cada
     * usuário; a cascata remove as famílias dele e os tokens delas.
     */
    public void cleanUp(ExecutorService threads) {
        threads.shutdownNow();
        emails.forEach(email -> jdbc.update("delete from users where email = ?", email));
    }
}
