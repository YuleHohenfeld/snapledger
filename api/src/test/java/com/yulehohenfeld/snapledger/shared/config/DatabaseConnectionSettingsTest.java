package com.yulehohenfeld.snapledger.shared.config;

import static com.yulehohenfeld.snapledger.support.LockWaits.LOCK_TIMEOUT;
import static org.assertj.core.api.Assertions.assertThat;

import java.sql.Connection;
import java.sql.SQLException;

import javax.sql.DataSource;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.data.jpa.test.autoconfigure.DataJpaTest;
import org.springframework.boot.jdbc.test.autoconfigure.AutoConfigureTestDatabase;
import org.springframework.context.annotation.Import;

import com.yulehohenfeld.snapledger.support.TestcontainersConfiguration;

/**
 * The session settings every pool connection gets from application.properties, on a real PostgreSQL.
 *
 * <p>PT: As configurações de sessão que toda conexão do pool recebe do application.properties, num
 * PostgreSQL real.
 * Notes: docs/code-notes/security.md#lock_timeout
 */
@DataJpaTest
@Import(TestcontainersConfiguration.class)
@AutoConfigureTestDatabase(replace = AutoConfigureTestDatabase.Replace.NONE)
class DatabaseConnectionSettingsTest {

    @Autowired
    DataSource dataSource;

    // Also ties LockWaits.LOCK_TIMEOUT, which the timing tests use, to the property.
    // PT: Também amarra o LockWaits.LOCK_TIMEOUT, que os testes de tempo usam, à propriedade.
    @Test
    void poolConnectionsHaveTheLockTimeout() throws SQLException {
        try (var connection = dataSource.getConnection()) {
            assertThat(show(connection)).isEqualTo(LOCK_TIMEOUT.toSeconds() + "s");
        }
    }

    // A startup option is the session default, so RESET ALL returns to it instead of to 0 (forever).
    // PT: Uma opção de inicialização é o padrão da sessão, então o RESET ALL volta para ela em vez de 0 (para sempre).
    @Test
    void theLockTimeoutSurvivesResetAll() throws SQLException {
        try (var connection = dataSource.getConnection(); var statement = connection.createStatement()) {
            statement.execute("set lock_timeout = 0");
            statement.execute("reset all");

            assertThat(show(connection)).isEqualTo(LOCK_TIMEOUT.toSeconds() + "s");
        }
    }

    private static String show(Connection connection) throws SQLException {
        try (var statement = connection.createStatement(); var result = statement.executeQuery("show lock_timeout")) {
            result.next();
            return result.getString(1);
        }
    }
}
