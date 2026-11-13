package com.yulehohenfeld.snapledger.user;

import static org.assertj.core.api.Assertions.assertThat;

import java.time.Instant;

import org.junit.jupiter.api.Test;
import org.mapstruct.factory.Mappers;

import tools.jackson.databind.json.JsonMapper;

import com.yulehohenfeld.snapledger.support.TestPasswordHashes;

/**
 * The generated mapper copies exactly the contract's UserResponse fields and never the password
 * hash. No Spring context: the generated class has a no-argument constructor.
 *
 * <p>PT: O mapper gerado copia exatamente os campos do UserResponse do contrato e nunca o hash da
 * senha. Sem contexto Spring: a classe gerada tem um construtor sem argumentos.
 */
class UserMapperTest {

    static final String HASH = TestPasswordHashes.BCRYPT;

    final UserMapper mapper = Mappers.getMapper(UserMapper.class);

    @Test
    void mapsEveryContractField() {
        var now = Instant.parse("2026-11-10T14:03:22Z");
        var user = User.register("Ana Souza", "ana@example.com", HASH, "USD", now);

        var response = mapper.toResponse(user);

        assertThat(response.id()).isEqualTo(user.getId());
        assertThat(response.name()).isEqualTo("Ana Souza");
        assertThat(response.email()).isEqualTo("ana@example.com");
        assertThat(response.currency()).isEqualTo("USD");
        assertThat(response.createdAt()).isEqualTo(now);
    }

    @Test
    void jsonHasOnlyTheContractFieldsAndNoHash() {
        var user = User.register("Ana Souza", "ana@example.com", HASH, "BRL", Instant.parse("2026-11-10T14:03:22Z"));

        var body = JsonMapper.builder().build().writeValueAsString(mapper.toResponse(user));

        assertThat(JsonMapper.builder().build().readTree(body).propertyNames())
                .containsExactlyInAnyOrder("id", "name", "email", "currency", "createdAt");
        assertThat(body).doesNotContain(HASH).doesNotContain("password");
    }
}
