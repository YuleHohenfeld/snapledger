package com.yulehohenfeld.snapledger.user.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import java.time.Clock;
import java.time.Instant;
import java.time.ZoneOffset;
import java.util.Optional;
import java.util.UUID;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mapstruct.factory.Mappers;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.dao.DataIntegrityViolationException;

import com.yulehohenfeld.snapledger.shared.error.EmailAlreadyRegisteredException;
import com.yulehohenfeld.snapledger.shared.error.UnauthorizedException;
import com.yulehohenfeld.snapledger.support.TestConstraintViolations;
import com.yulehohenfeld.snapledger.support.TestPasswordHashes;

/**
 * UserService rules with the repository mocked; the real generated mapper is used.
 *
 * <p>PT: Regras do UserService com o repositório simulado; o mapper gerado real é usado.
 */
@ExtendWith(MockitoExtension.class)
class UserServiceTest {

    static final Instant NOW = Instant.parse("2026-11-13T10:00:00Z");
    static final String HASH = TestPasswordHashes.BCRYPT;

    @Mock
    UserRepository users;

    UserService service;

    @BeforeEach
    void setUp() {
        service = new UserService(users, Mappers.getMapper(UserMapper.class), Clock.fixed(NOW, ZoneOffset.UTC));
    }

    @Test
    void createInsertsImmediatelyWithLowercaseEmailAndReturnsTheResponse() {
        var saved = ArgumentCaptor.forClass(User.class);
        when(users.saveAndFlush(saved.capture())).thenAnswer(invocation -> invocation.getArgument(0));

        var response = service.create("Ana Souza", "Ana@Example.COM", HASH, "USD");

        var user = saved.getValue();
        assertThat(user.getEmail()).isEqualTo("ana@example.com");
        assertThat(user.getPasswordHash()).isEqualTo(HASH);
        assertThat(user.getCreatedAt()).isEqualTo(NOW);
        assertThat(response.id()).isEqualTo(user.getId());
        assertThat(response.email()).isEqualTo("ana@example.com");
        assertThat(response.currency()).isEqualTo("USD");
        assertThat(response.createdAt()).isEqualTo(NOW);
    }

    @Test
    void createTurnsTheEmailConstraintIntoEmailAlreadyRegistered() {
        when(users.saveAndFlush(any())).thenThrow(violationOf("uk_users_email"));

        assertThatThrownBy(() -> service.create("Ana", "ana@example.com", HASH, "BRL"))
                .isInstanceOf(EmailAlreadyRegisteredException.class)
                .hasNoCause();
    }

    // Any other constraint is a bug or a schema problem, never a 409: it must reach the masked 500.
    // PT: Qualquer outra constraint é bug ou problema de esquema, nunca 409: precisa chegar ao 500 mascarado.
    @Test
    void createPropagatesAnyOtherConstraintViolation() {
        var other = violationOf("ck_users_password_hash_bcrypt");
        when(users.saveAndFlush(any())).thenThrow(other);

        assertThatThrownBy(() -> service.create("Ana", "ana@example.com", HASH, "BRL")).isSameAs(other);
    }

    @Test
    void createPropagatesAViolationWithoutConstraintName() {
        var unnamed = new DataIntegrityViolationException("could not execute statement");
        when(users.saveAndFlush(any())).thenThrow(unnamed);

        assertThatThrownBy(() -> service.create("Ana", "ana@example.com", HASH, "BRL")).isSameAs(unnamed);
    }

    @Test
    void findCredentialsNormalizesTheEmailAndReturnsHashAndProfile() {
        var user = User.register("Ana", "ana@example.com", HASH, "BRL", NOW);
        when(users.findByEmail("ana@example.com")).thenReturn(Optional.of(user));

        var credentials = service.findCredentials("ANA@example.com").orElseThrow();

        assertThat(credentials.passwordHash()).isEqualTo(HASH);
        assertThat(credentials.user().id()).isEqualTo(user.getId());
        assertThat(credentials.toString()).doesNotContain(HASH).doesNotContain("ana@example.com");
    }

    @Test
    void findCredentialsIsEmptyForAnUnknownEmail() {
        when(users.findByEmail("nobody@example.com")).thenReturn(Optional.empty());

        assertThat(service.findCredentials("nobody@example.com")).isEmpty();
    }

    @Test
    void getCurrentReturnsTheProfile() {
        var user = User.register("Ana", "ana@example.com", HASH, "BRL", NOW);
        when(users.findById(user.getId())).thenReturn(Optional.of(user));

        assertThat(service.getCurrent(user.getId()).name()).isEqualTo("Ana");
    }

    // Contract: a valid token whose user no longer exists is 401 unauthorized, not 404.
    // PT: Contrato: um token válido cujo usuário não existe mais é 401 unauthorized, não 404.
    @Test
    void getCurrentThrowsUnauthorizedWhenTheUserNoLongerExists() {
        var gone = UUID.randomUUID();
        when(users.findById(gone)).thenReturn(Optional.empty());

        assertThatThrownBy(() -> service.getCurrent(gone)).isInstanceOf(UnauthorizedException.class);
        verify(users).findById(gone);
    }

    private static DataIntegrityViolationException violationOf(String constraint) {
        return TestConstraintViolations.translated(constraint);
    }
}
