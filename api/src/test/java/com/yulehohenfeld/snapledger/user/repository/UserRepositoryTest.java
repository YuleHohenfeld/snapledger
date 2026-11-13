package com.yulehohenfeld.snapledger.user.repository;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.UUID;
import java.util.stream.Stream;

import jakarta.persistence.PersistenceException;
import jakarta.persistence.Query;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.CsvSource;
import org.junit.jupiter.params.provider.MethodSource;
import org.junit.jupiter.params.provider.ValueSource;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.data.jpa.test.autoconfigure.DataJpaTest;
import org.springframework.boot.jdbc.test.autoconfigure.AutoConfigureTestDatabase;
import org.springframework.boot.jpa.test.autoconfigure.TestEntityManager;
import org.springframework.context.annotation.Import;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder.BCryptVersion;
import org.springframework.security.crypto.factory.PasswordEncoderFactories;

import com.yulehohenfeld.snapledger.support.TestPasswordHashes;
import com.yulehohenfeld.snapledger.support.TestcontainersConfiguration;
import com.yulehohenfeld.snapledger.user.entity.User;

/**
 * V1 against a real PostgreSQL: the mapping passes ddl-auto=validate (the context would not start
 * otherwise), the login lookup works and the constraints refuse what the contract forbids, even
 * when the application is bypassed with plain SQL.
 *
 * <p>PT: A V1 contra um PostgreSQL real: o mapeamento passa no ddl-auto=validate (senão o contexto
 * nem subiria), a busca do login funciona e as constraints recusam o que o contrato proíbe, mesmo
 * quando a aplicação é contornada com SQL puro.
 */
@DataJpaTest
@Import(TestcontainersConfiguration.class)
@AutoConfigureTestDatabase(replace = AutoConfigureTestDatabase.Replace.NONE)
class UserRepositoryTest {

    static final Instant NOW = Instant.parse("2026-11-12T10:00:00Z");
    static final String HASH = TestPasswordHashes.BCRYPT;
    static final String EMOJI = "😀";

    @Autowired
    UserRepository users;

    @Autowired
    TestEntityManager entityManager;

    @Test
    void savesARegisteredUserAndFindsItByEmail() {
        var saved = users.save(User.register("  Ana Souza ", "Ana@Example.com", HASH, "BRL", NOW));
        entityManager.flush();
        entityManager.clear();

        var found = users.findByEmail("ana@example.com").orElseThrow();

        assertThat(found.getId()).isEqualTo(saved.getId());
        assertThat(found.getName()).isEqualTo("Ana Souza");
        assertThat(found.getEmail()).isEqualTo("ana@example.com");
        assertThat(found.getPasswordHash()).isEqualTo(HASH);
        assertThat(found.getCurrency()).isEqualTo("BRL");
        assertThat(found.getCreatedAt()).isEqualTo(NOW);
    }

    @Test
    void findByEmailIsEmptyForAnUnknownEmail() {
        users.save(User.register("Ana", "ana@example.com", HASH, "BRL", NOW));

        assertThat(users.findByEmail("bruno@example.com")).isEmpty();
    }

    // save() returns the same instance: Spring Data called persist, not merge (which would copy
    // the entity after an extra SELECT). That is what the AssignedIdEntity flag is for. The flag
    // flips when the INSERT really runs, at flush (@PostPersist).
    // PT: O save() devolve a mesma instância: o Spring Data chamou persist, e não merge (que
    //     copiaria a entidade depois de um SELECT extra). É para isso que serve a flag do
    //     AssignedIdEntity. A flag vira quando o INSERT realmente roda, no flush (@PostPersist).
    @Test
    void saveOfANewUserPersistsInsteadOfMerging() {
        var user = User.register("Ana", "ana@example.com", HASH, "BRL", NOW);
        assertThat(user.isNew()).isTrue();

        var saved = users.save(user);
        entityManager.flush();

        assertThat(saved).isSameAs(user);
        assertThat(saved.isNew()).isFalse();
    }

    @Test
    void loadedUserIsNotNew() {
        var id = users.save(User.register("Ana", "ana@example.com", HASH, "BRL", NOW)).getId();
        entityManager.flush();
        entityManager.clear();

        assertThat(users.findById(id).orElseThrow().isNew()).isFalse();
    }

    // The constraint, not a prior "exists?" query, is the guard against two concurrent
    // registrations; its name is what the register flow will recognize.
    // PT: A constraint, e não uma consulta "existe?" antes, é a proteção contra dois cadastros
    //     simultâneos; o nome dela é o que o fluxo de cadastro vai reconhecer.
    @Test
    void duplicateEmailInAnyCaseViolatesTheUniqueConstraint() {
        users.saveAndFlush(User.register("Ana", "ana@example.com", HASH, "BRL", NOW));

        assertThatThrownBy(() -> users.saveAndFlush(User.register("Other", "ANA@example.com", HASH, "USD", NOW)))
                .isInstanceOf(DataIntegrityViolationException.class)
                .rootCause().hasMessageContaining("uk_users_email");
    }

    @Test
    void timestampsKeepMicrosecondPrecision() {
        var precise = Instant.parse("2026-11-12T10:00:00.123456Z");
        var id = users.save(User.register("Ana", "ana@example.com", HASH, "BRL", precise)).getId();
        entityManager.flush();
        entityManager.clear();

        assertThat(users.findById(id).orElseThrow().getCreatedAt()).isEqualTo(precise.truncatedTo(ChronoUnit.MICROS));
    }

    @Test
    void toStringShowsOnlyTheId() {
        var user = User.register("Ana Souza", "ana@example.com", HASH, "BRL", NOW);

        assertThat(user.toString())
                .contains(user.getId().toString())
                .doesNotContain("Ana")
                .doesNotContain("ana@example.com")
                .doesNotContain(HASH);
    }

    // varchar(80) counts code points: 80 emoji (160 Java chars, 320 UTF-8 bytes) fit, 81 do not.
    // Same unit as @CodePointLength on the request, so a valid request always fits the column.
    // PT: O varchar(80) conta code points: 80 emojis (160 chars do Java, 320 bytes UTF-8) cabem, 81
    //     não. Mesma unidade do @CodePointLength da requisição, então uma requisição válida sempre
    //     cabe na coluna.
    @Test
    void nameColumnHolds80CodePointsNot80Bytes() {
        var name = EMOJI.repeat(80);
        var id = users.save(User.register(name, "ana@example.com", HASH, "BRL", NOW)).getId();
        entityManager.flush();
        entityManager.clear();

        assertThat(users.findById(id).orElseThrow().getName()).isEqualTo(name);
        assertThatThrownBy(insert(EMOJI.repeat(81), "bruno@example.com", HASH, "BRL")::executeUpdate)
                .isInstanceOf(PersistenceException.class)
                .rootCause().hasMessageContaining("character varying(80)");
    }

    @ParameterizedTest(name = "{0}")
    @CsvSource(delimiter = '|', textBlock = """
            uppercase email          | Ana        | Ana@example.com  | BRL | ck_users_email_lowercase
            accented email           | Ana        | josé@example.com | BRL | ck_users_email_ascii_no_whitespace
            leading space in email   | Ana        | ' ana@x.com'     | BRL | ck_users_email_ascii_no_whitespace
            inner space in email     | Ana        | 'ana @x.com'     | BRL | ck_users_email_ascii_no_whitespace
            tab in email             | Ana        | 'ana\t@x.com'    | BRL | ck_users_email_ascii_no_whitespace
            untrimmed name           | ' Ana '    | ana@example.com  | BRL | ck_users_name_trimmed
            empty name               | ''         | ana@example.com  | BRL | ck_users_name_trimmed
            tab inside name          | 'Ana\tLu'  | ana@example.com  | BRL | ck_users_name_no_control_chars
            lowercase currency       | Ana        | ana@example.com  | brl | ck_users_currency_format
            numeric currency         | Ana        | ana@example.com  | 123 | ck_users_currency_format
            """)
    void databaseRejectsWhatTheContractForbidsEvenWithoutTheApplication(
            String description, String name, String email, String currency, String constraint) {
        assertThatThrownBy(insert(name, email, HASH, currency)::executeUpdate)
                .isInstanceOf(PersistenceException.class)
                .rootCause().hasMessageContaining(constraint);
    }

    // C0 and C1 control characters inside the name, where btrim cannot see them.
    // PT: Caracteres de controle C0 e C1 dentro do nome, onde o btrim não os enxerga.
    @ParameterizedTest
    @ValueSource(strings = {"Ana\u0001Lu", "Ana\u001bLu", "Ana\nLu", "Ana\u007fLu", "Ana\u0085Lu", "Ana\u009fLu"})
    void databaseRejectsControlCharactersInTheName(String name) {
        assertThatThrownBy(insert(name, "ana@example.com", HASH, "BRL")::executeUpdate)
                .isInstanceOf(PersistenceException.class)
                .rootCause().hasMessageContaining("ck_users_name_no_control_chars");
    }

    // Visible Unicode outside the control ranges is a valid name for the database.
    // PT: Unicode visível fora das faixas de controle é um nome válido para o banco.
    @Test
    void databaseAcceptsAccentsAndEmojiInTheName() {
        assertThat(insert("José " + EMOJI + " Ñandú", "ana@example.com", HASH, "BRL").executeUpdate()).isEqualTo(1);
    }

    /**
     * Everything Spring's encoders produce, with or without the {bcrypt} prefix of the
     * DelegatingPasswordEncoder, so Step 3 can pick either one.
     *
     * <p>PT: Tudo que os encoders do Spring produzem, com ou sem o prefixo {bcrypt} do
     * DelegatingPasswordEncoder, para que o passo 3 possa escolher qualquer um dos dois.
     */
    static Stream<String> hashesSpringProduces() {
        var password = UUID.randomUUID().toString();
        return Stream.of(
                new BCryptPasswordEncoder(4).encode(password),
                new BCryptPasswordEncoder(BCryptVersion.$2B, 4).encode(password),
                new BCryptPasswordEncoder(BCryptVersion.$2Y, 4).encode(password),
                new BCryptPasswordEncoder().encode(password),
                PasswordEncoderFactories.createDelegatingPasswordEncoder().encode(password));
    }

    @ParameterizedTest
    @MethodSource("hashesSpringProduces")
    void databaseAcceptsEveryBcryptFormatSpringProduces(String hash) {
        assertThat(insert("Ana", "ana@example.com", hash, "BRL").executeUpdate()).isEqualTo(1);
    }

    static Stream<String> valuesThatAreNotBcryptHashes() {
        var hash = TestPasswordHashes.BCRYPT;
        return Stream.of(
                "plain-text-password",
                "{noop}plain-text-password",
                hash.substring(0, hash.length() - 1),       // truncated
                // PT: truncado
                hash + "x",                                  // one character too many
                // PT: um caractere a mais
                hash.replace("$2a$", "$2x$"),                // unknown version
                // PT: versão desconhecida
                "{sha256}" + hash,                           // another encoder's prefix
                // PT: prefixo de outro encoder
                "");
    }

    @ParameterizedTest
    @MethodSource("valuesThatAreNotBcryptHashes")
    void databaseRejectsAPasswordHashThatIsNotBcrypt(String notAHash) {
        assertThatThrownBy(insert("Ana", "ana@example.com", notAHash, "BRL")::executeUpdate)
                .isInstanceOf(PersistenceException.class)
                .rootCause().hasMessageContaining("ck_users_password_hash_bcrypt");
    }

    private Query insert(String name, String email, String hash, String currency) {
        return entityManager.getEntityManager().createNativeQuery("""
                insert into users (id, name, email, password_hash, currency, created_at)
                values (?1, ?2, ?3, ?4, ?5, ?6)
                """)
                .setParameter(1, UUID.randomUUID())
                .setParameter(2, name)
                .setParameter(3, email)
                .setParameter(4, hash)
                .setParameter(5, currency)
                .setParameter(6, NOW);
    }
}
