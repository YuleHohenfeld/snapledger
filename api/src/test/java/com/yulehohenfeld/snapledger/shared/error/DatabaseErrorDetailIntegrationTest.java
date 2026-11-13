package com.yulehohenfeld.snapledger.shared.error;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.catchThrowable;

import java.io.PrintWriter;
import java.io.StringWriter;
import java.sql.DriverManager;
import java.sql.SQLException;
import java.util.Locale;
import java.util.Properties;
import java.util.UUID;

import javax.sql.DataSource;

import jakarta.persistence.EntityManager;

import com.zaxxer.hikari.HikariDataSource;

import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.logging.LogLevel;
import org.springframework.boot.logging.LoggingSystem;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.system.CapturedOutput;
import org.springframework.boot.test.system.OutputCaptureExtension;
import org.springframework.context.annotation.Import;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.dao.DuplicateKeyException;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.orm.jpa.vendor.HibernateJpaDialect;
import org.springframework.transaction.support.TransactionTemplate;

import com.yulehohenfeld.snapledger.support.TestJwtSecret;
import com.yulehohenfeld.snapledger.support.TestcontainersConfiguration;

/**
 * {@code logServerErrorDetail=false} (application.properties) against a real PostgreSQL: a unique
 * violation must not carry the duplicated value anywhere in the exception, its causes or its stack
 * trace, so no logger can print it. Values PostgreSQL puts in the primary message are kept out of
 * Hibernate's log by logback-spring.xml (also tested here). Same context as
 * SnapledgerApplicationTests, so the cached context and its container are reused.
 *
 * <p>PT: {@code logServerErrorDetail=false} (application.properties) contra um PostgreSQL real: uma
 * violação de unicidade não pode levar o valor duplicado em nenhum lugar da exceção, das causas ou
 * do stack trace, então nenhum logger consegue imprimi-lo. Valores que o PostgreSQL coloca na
 * mensagem principal ficam fora do log do Hibernate por causa do logback-spring.xml (também testado
 * aqui). Mesmo contexto do
 * SnapledgerApplicationTests, então o contexto em cache e o seu container são reaproveitados.
 */
@ExtendWith(OutputCaptureExtension.class)
@SpringBootTest
@Import({TestcontainersConfiguration.class, TestJwtSecret.class})
class DatabaseErrorDetailIntegrationTest {

    static final String EMAIL = "erin.secret@example.com";
    static final String OTHER_EMAIL = "bind.secret@example.com";
    static final String HIBERNATE_JDBC = "org.hibernate.orm.jdbc";
    static final String HIBERNATE_JDBC_ERROR = HIBERNATE_JDBC + ".error";
    static final String HIBERNATE_JDBC_BIND = HIBERNATE_JDBC + ".bind";

    @Autowired
    DataSource dataSource;

    @Autowired
    JdbcTemplate jdbc;

    @Autowired
    EntityManager entityManager;

    @Autowired
    TransactionTemplate transactions;

    // A random table name per run: no migration owns it and it is dropped after each test.
    // PT: Um nome de tabela aleatório por execução: nenhuma migration é dona dela, e ela é apagada
    //     depois de cada teste.
    private final String table = "probe_" + UUID.randomUUID().toString().replace("-", "");

    @BeforeEach
    void createTable() {
        jdbc.execute("create table " + table + " (email text not null, constraint uk_" + table + " unique (email))");
        jdbc.update("insert into " + table + " (email) values (?)", EMAIL);
    }

    @AfterEach
    void dropTable() {
        jdbc.execute("drop table if exists " + table);
    }

    @Test
    void uniqueViolationThroughTheApplicationDataSourceDoesNotQuoteTheValue() {
        var failure = catchThrowable(() -> jdbc.update("insert into " + table + " (email) values (?)", EMAIL));

        assertThat(failure).isInstanceOf(DuplicateKeyException.class);
        assertThat(everythingPrintable(failure))
                .contains("uk_" + table)
                .doesNotContain(EMAIL);
    }

    /**
     * Register (Increment 2 Step 3) will answer a duplicate email with 409 email-already-registered
     * by recognizing the violated constraint by name. This proves that is still possible with
     * logServerErrorDetail=false: the insert goes through Hibernate (the dialect extracts the name
     * from PostgreSQL's primary message) and Spring's JPA translation (what a repository proxy does),
     * and InternalErrors.constraintName finds the name in the result. users itself uses a plain
     * unique constraint, uk_users_email, on an email stored lowercase (UserRepositoryTest covers
     * it). This probe uses a unique index on lower(email) instead, and the duplicate differs only in
     * case, so only that index can be what failed: the name is extracted even from an expression
     * index, the harder case.
     *
     * <p>PT: O cadastro (entrega 2, passo 3) vai responder um email duplicado com 409
     * email-already-registered reconhecendo a constraint violada pelo nome. Isto prova que isso
     * continua possível com logServerErrorDetail=false: o insert passa pelo Hibernate (o dialeto
     * extrai o nome da mensagem principal do PostgreSQL) e pela tradução JPA do Spring (o que o proxy
     * de um repository faz), e o InternalErrors.constraintName encontra o nome no resultado. A
     * própria users usa uma unique simples, uk_users_email, sobre um email gravado em minúsculas (o
     * UserRepositoryTest cobre isso). Esta sonda usa um índice único sobre lower(email), e o
     * duplicado difere só em maiúsculas, então só esse índice pode ser o que falhou: o nome é
     * extraído até de um índice de expressão, o caso mais difícil.
     */
    @Test
    void constraintNameOfACaseInsensitiveUniqueIndexSurvivesWithoutTheValue() {
        var index = "uk_" + table + "_lower";
        jdbc.execute("create unique index " + index + " on " + table + " (lower(email))");
        var duplicate = EMAIL.toUpperCase(Locale.ROOT);

        var failure = catchThrowable(() -> transactions.executeWithoutResult(status -> entityManager
                .createNativeQuery("insert into " + table + " (email) values (:email)")
                .setParameter("email", duplicate)
                .executeUpdate()));
        var translated = new HibernateJpaDialect().translateExceptionIfPossible((RuntimeException) failure);

        assertThat(translated).isInstanceOf(DataIntegrityViolationException.class);
        assertThat(InternalErrors.constraintName(translated)).isEqualTo(index);
        assertThat(everythingPrintable(translated))
                .doesNotContain(EMAIL)
                .doesNotContain(duplicate);
    }

    // Positive control: the same insert on a connection that keeps the driver default does quote
    // the value, so the test above passes because of the property and not by accident.
    // PT: Controle positivo: o mesmo insert numa conexão que mantém o padrão do driver cita o
    //     valor, então o teste acima passa por causa da propriedade e não por acaso.
    @Test
    void driverDefaultWouldQuoteTheValue() throws SQLException {
        var hikari = (HikariDataSource) dataSource;
        var properties = new Properties();
        properties.setProperty("user", hikari.getUsername());
        properties.setProperty("password", hikari.getPassword());
        properties.setProperty("logServerErrorDetail", "true");

        try (var connection = DriverManager.getConnection(hikari.getJdbcUrl(), properties);
             var insert = connection.prepareStatement("insert into " + table + " (email) values (?)")) {
            insert.setString(1, EMAIL);
            var failure = catchThrowable(insert::executeUpdate);

            assertThat(everythingPrintable(failure)).contains(EMAIL);
        }
    }

    /**
     * A PostgreSQL primary message that quotes the value (22P02) passes through Hibernate, which
     * would log it under org.hibernate.orm.jdbc.error; logback-spring.xml turns that logger off. Native query
     * through the EntityManager: no entity or migration is needed for Hibernate to be on the path.
     *
     * <p>PT: Uma mensagem principal do PostgreSQL que cita o valor (22P02) passa pelo Hibernate, que
     * a registraria em org.hibernate.orm.jdbc.error; o logback-spring.xml desliga esse logger. Query nativa
     * pelo EntityManager: nenhuma entidade ou migration é necessária para o Hibernate estar no
     * caminho.
     */
    @Test
    void hibernateDoesNotLogADriverMessageThatQuotesTheValue(CapturedOutput output) {
        var failure = castEmailToUuid();

        assertThat(failure).isNotNull();
        assertThat(everythingPrintable(failure)).contains(EMAIL); // the message itself does carry it
        // PT: a própria mensagem carrega o valor
        assertThat(output.getAll()).doesNotContain(EMAIL).doesNotContain(HIBERNATE_JDBC_ERROR);
    }

    // Positive control: with the logger back at its default level the same query logs the value,
    // so the test above passes because of logback-spring.xml and not because Hibernate stays quiet.
    // PT: Controle positivo: com o logger de volta ao nível padrão, a mesma query registra o valor,
    //     então o teste acima passa por causa do logback-spring.xml e não porque o Hibernate fica
    //     calado.
    @Test
    void hibernateWouldLogTheValueWithTheLoggerOn(CapturedOutput output) {
        var logging = LoggingSystem.get(getClass().getClassLoader());
        logging.setLogLevel(HIBERNATE_JDBC_ERROR, LogLevel.WARN);
        try {
            castEmailToUuid();
        } finally {
            logging.setLogLevel(HIBERNATE_JDBC_ERROR, LogLevel.OFF);
        }

        assertThat(output.getAll()).contains(HIBERNATE_JDBC_ERROR).contains(EMAIL);
    }

    /**
     * logback-spring.xml pins org.hibernate.orm.jdbc.bind to INFO, so raising its parent to TRACE
     * (the usual way to "see the SQL parameters") does not print bound values. An insert binds the
     * email and extracts nothing, so only the binding logger could print it.
     *
     * <p>PT: O logback-spring.xml fixa o org.hibernate.orm.jdbc.bind em INFO, então subir o pai dele
     * para TRACE (o jeito comum de "ver os parâmetros do SQL") não imprime valores ligados. Um
     * insert liga o email e não extrai nada, então só o logger de binding poderia imprimi-lo.
     */
    @Test
    void hibernateDoesNotLogBoundValuesWhenItsParentIsAtTrace(CapturedOutput output) {
        withLogLevel(HIBERNATE_JDBC, LogLevel.TRACE, null, this::insertAnotherEmail);

        assertThat(output.getAll()).doesNotContain(OTHER_EMAIL).doesNotContain("binding parameter");
    }

    // Positive control: with the binding logger itself at TRACE (the pin removed) the same insert
    // prints the value, so the test above passes because of the pin, under the name Hibernate uses.
    // PT: Controle positivo: com o próprio logger de binding em TRACE (sem a fixação), o mesmo insert
    //     imprime o valor, então o teste acima passa por causa da fixação, com o nome que o
    //     Hibernate usa.
    @Test
    void hibernateWouldLogBoundValuesWithoutThePin(CapturedOutput output) {
        withLogLevel(HIBERNATE_JDBC_BIND, LogLevel.TRACE, LogLevel.INFO, this::insertAnotherEmail);

        assertThat(output.getAll()).contains("binding parameter").contains(OTHER_EMAIL);
    }

    private void insertAnotherEmail() {
        transactions.executeWithoutResult(status -> entityManager
                .createNativeQuery("insert into " + table + " (email) values (:email)")
                .setParameter("email", OTHER_EMAIL)
                .executeUpdate());
    }

    /**
     * Runs the action with {@code name} at {@code level}, then puts back {@code restore} (null =
     * inherited, as without logback-spring.xml), so later tests see the real configuration.
     *
     * <p>PT: Executa a ação com {@code name} em {@code level} e depois devolve {@code restore} (null
     * = herdado, como sem o logback-spring.xml), para que os testes seguintes vejam a configuração real.
     */
    private static void withLogLevel(String name, LogLevel level, LogLevel restore, Runnable action) {
        var logging = LoggingSystem.get(DatabaseErrorDetailIntegrationTest.class.getClassLoader());
        logging.setLogLevel(name, level);
        try {
            action.run();
        } finally {
            logging.setLogLevel(name, restore);
        }
    }

    private Throwable castEmailToUuid() {
        return catchThrowable(() -> entityManager.createNativeQuery("select cast(:value as uuid)")
                .setParameter("value", EMAIL)
                .getSingleResult());
    }

    /**
     * What a logger can print: toString and stack trace of the whole chain.
     *
     * <p>PT: O que um logger consegue imprimir: toString e stack trace da cadeia inteira.
     */
    private static String everythingPrintable(Throwable failure) {
        var out = new StringWriter();
        failure.printStackTrace(new PrintWriter(out));
        return out.toString();
    }
}
