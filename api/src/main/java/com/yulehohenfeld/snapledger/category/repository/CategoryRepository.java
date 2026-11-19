package com.yulehohenfeld.snapledger.category.repository;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;

import com.yulehohenfeld.snapledger.category.entity.Category;

/** Categories visible to a user (defaults + own); name uniqueness comes from the indexes, not from a query.
 *  PT: Categorias visíveis a um usuário (padrão + próprias); a unicidade do nome vem dos índices, não de consulta.
 *  Notes: docs/code-notes/category.md#categoryrepository */
public interface CategoryRepository extends JpaRepository<Category, UUID> {

    /** Defaults first, then own, each group by lower(name). PT: Padrão primeiro, depois as próprias, cada grupo por lower(name). */
    @Query("""
            select c from Category c
            where c.userId is null or c.userId = :userId
            order by case when c.userId is null then 0 else 1 end, lower(c.name), c.id
            """)
    List<Category> findVisible(UUID userId);

    /** Ownership in the query: another user's category is empty here. PT: A posse está na query: categoria de outro usuário vem vazia. */
    @Query("select c from Category c where c.id = :id and (c.userId is null or c.userId = :userId)")
    Optional<Category> findVisibleById(UUID id, UUID userId);

    /** Notes: docs/code-notes/category.md#default-name-clash
     *  PT: Existe uma categoria padrão com este nome, sem diferenciar maiúsculas? */
    @Query("select count(c) > 0 from Category c where c.userId is null and lower(c.name) = lower(:name)")
    boolean existsDefaultNamedIgnoreCase(String name);
}
