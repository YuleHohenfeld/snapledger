package com.yulehohenfeld.snapledger.shared.persistence;

import java.util.Objects;
import java.util.UUID;

import jakarta.persistence.Id;
import jakarta.persistence.MappedSuperclass;
import jakarta.persistence.PostLoad;
import jakarta.persistence.PostPersist;
import jakarta.persistence.Transient;

import lombok.AccessLevel;
import lombok.Getter;

import org.springframework.data.domain.Persistable;

/**
 * Base of every entity whose UUID is assigned by the application (in its factory method) instead
 * of by the database. Spring Data decides between persist and merge with {@code isNew()}; its
 * default looks for a null id, which never happens here, so every save of a new entity would be a
 * merge: an extra SELECT before the INSERT. The transient flag answers {@code isNew()} instead and
 * flips when the row is inserted (@PostPersist) or loaded (@PostLoad). JPA applies callbacks
 * declared on a mapped superclass to every subclass.
 *
 * <p>equals/hashCode are not overridden (object identity). Inside one persistence context
 * Hibernate keeps one instance per row, so identity is correct there; entities are never compared
 * across contexts or kept in hash sets. An id-based equals would have to deal with Hibernate
 * proxies, which is the bug api/CLAUDE.md warns about.
 *
 * <p>PT: Base de toda entidade cujo UUID é atribuído pela aplicação (no método de fábrica) e não
 * pelo banco. O Spring Data decide entre persist e merge com o {@code isNew()}; o padrão dele
 * procura um id nulo, o que nunca acontece aqui, então todo save de uma entidade nova seria um
 * merge: um SELECT extra antes do INSERT. A flag transiente responde o {@code isNew()} no lugar e
 * vira quando a linha é inserida (@PostPersist) ou carregada (@PostLoad). O JPA aplica callbacks
 * declarados numa mapped superclass a todas as subclasses. O equals/hashCode não é sobrescrito
 * (identidade do objeto). Dentro de um mesmo contexto de persistência o Hibernate mantém uma
 * instância por linha, então a identidade está correta ali; entidades nunca são comparadas entre
 * contextos nem guardadas em hash sets. Um equals por id teria que lidar com os proxies do
 * Hibernate, que é o bug sobre o qual o api/CLAUDE.md alerta.
 */
@MappedSuperclass
@Getter
public abstract class AssignedIdEntity implements Persistable<UUID> {

    @Id
    private UUID id;

    @Transient
    @Getter(AccessLevel.NONE)
    private boolean persisted;

    /**
     * For JPA only: Hibernate fills the id from the row.
     *
     * <p>PT: Só para o JPA: o Hibernate preenche o id a partir da linha.
     */
    protected AssignedIdEntity() {
    }

    /**
     * For the factory methods of subclasses: a new entity, not yet in the database.
     *
     * <p>PT: Para os métodos de fábrica das subclasses: uma entidade nova, ainda fora do banco.
     */
    protected AssignedIdEntity(UUID id) {
        this.id = Objects.requireNonNull(id, "id");
    }

    @Override
    public boolean isNew() {
        return !persisted;
    }

    @PostPersist
    @PostLoad
    void markPersisted() {
        persisted = true;
    }
}
