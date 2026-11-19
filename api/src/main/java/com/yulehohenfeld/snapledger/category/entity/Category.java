package com.yulehohenfeld.snapledger.category.entity;

import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.UUID;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Table;

import lombok.AccessLevel;
import lombok.Getter;
import lombok.NoArgsConstructor;

import com.yulehohenfeld.snapledger.shared.persistence.AssignedIdEntity;

/** A default (no user) or own category; own ones are built only by {@link #createOwn}.
 *  PT: Uma categoria padrão (sem usuário) ou própria; as próprias nascem só do {@link #createOwn}.
 *  Notes: docs/code-notes/category.md#category */
@Entity
@Table(name = "categories")
@Getter
@NoArgsConstructor(access = AccessLevel.PROTECTED) // JPA only
// PT: só para o JPA
public class Category extends AssignedIdEntity {

    @Column(name = "user_id", updatable = false)
    private UUID userId;

    @Column(name = "key", length = 30, updatable = false)
    private String key;

    @Column(nullable = false, length = 40)
    private String name;

    @Column(name = "created_at", nullable = false, updatable = false)
    private Instant createdAt;

    private Category(UUID id) {
        super(id);
    }

    /** A new category of the user; the caller has already validated the name.
     *  PT: Uma categoria nova do usuário; quem chama já validou o nome. */
    public static Category createOwn(UUID userId, String name, Instant now) {
        var category = new Category(UUID.randomUUID());
        category.userId = userId;
        category.name = name.strip();
        category.createdAt = now.truncatedTo(ChronoUnit.MICROS);
        return category;
    }

    /** True for the seeded categories, shared by every user. PT: Verdadeiro para as categorias do seed, de todos os usuários. */
    public boolean isDefault() {
        return userId == null;
    }

    /** Renames an own category; a default one is never renamed (the service answers 403 first).
     *  PT: Renomeia uma categoria própria; uma padrão nunca é renomeada (o service responde 403 antes). */
    public void rename(String newName) {
        if (isDefault()) {
            throw new IllegalStateException("A default category cannot be renamed");
        }
        this.name = newName.strip();
    }

    // Only the id: the name is user text and never reaches a log.
    // PT: Só o id: o nome é texto do usuário e nunca chega a um log.
    @Override
    public String toString() {
        return "Category[id=" + getId() + "]";
    }
}
