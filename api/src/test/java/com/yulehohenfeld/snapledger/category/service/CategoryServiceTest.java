package com.yulehohenfeld.snapledger.category.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import java.time.Clock;
import java.time.Instant;
import java.time.ZoneOffset;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mapstruct.factory.Mappers;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.orm.ObjectOptimisticLockingFailureException;

import com.yulehohenfeld.snapledger.category.dto.CategoryRequest;
import com.yulehohenfeld.snapledger.category.entity.Category;
import com.yulehohenfeld.snapledger.category.mapper.CategoryMapper;
import com.yulehohenfeld.snapledger.category.repository.CategoryRepository;
import com.yulehohenfeld.snapledger.shared.error.CategoryInUseException;
import com.yulehohenfeld.snapledger.shared.error.CategoryNameTakenException;
import com.yulehohenfeld.snapledger.shared.error.DefaultCategoryReadOnlyException;
import com.yulehohenfeld.snapledger.shared.error.NotFoundException;
import com.yulehohenfeld.snapledger.support.TestConstraintViolations;

/**
 * Category rules with the repository mocked; the database side is proven in CategoryRepositoryTest.
 *
 * <p>PT: Regras de categoria com o repository simulado; o lado do banco é provado no CategoryRepositoryTest.
 */
@ExtendWith(MockitoExtension.class)
class CategoryServiceTest {

    static final Instant NOW = Instant.parse("2026-11-12T10:00:00Z");

    @Mock
    CategoryRepository categories;

    CategoryService service;

    final UUID userId = UUID.randomUUID();

    @BeforeEach
    void createService() {
        service = new CategoryService(categories, Mappers.getMapper(CategoryMapper.class),
                Clock.fixed(NOW, ZoneOffset.UTC));
    }

    @Test
    void listReturnsTheVisibleCategoriesAsResponses() {
        var own = Category.createOwn(userId, "Pets", NOW);
        when(categories.findVisible(userId)).thenReturn(List.of(own));

        var result = service.list(userId);

        assertThat(result).singleElement().satisfies(r -> {
            assertThat(r.id()).isEqualTo(own.getId());
            assertThat(r.name()).isEqualTo("Pets");
            assertThat(r.isDefault()).isFalse();
            assertThat(r.key()).isNull();
        });
    }

    @Test
    void createInsertsATrimmedOwnCategoryStampedWithTheClock() {
        var result = service.create(userId, new CategoryRequest("  Pets  "));

        var saved = org.mockito.ArgumentCaptor.forClass(Category.class);
        verify(categories).saveAndFlush(saved.capture());
        assertThat(saved.getValue().getUserId()).isEqualTo(userId);
        assertThat(saved.getValue().getName()).isEqualTo("Pets");
        assertThat(saved.getValue().getCreatedAt()).isEqualTo(NOW);
        assertThat(result.name()).isEqualTo("Pets");
        assertThat(result.isDefault()).isFalse();
    }

    @Test
    void createRejectsANameThatClashesWithADefaultWithoutInserting() {
        when(categories.existsDefaultNamedIgnoreCase("food")).thenReturn(true);

        assertThatThrownBy(() -> service.create(userId, new CategoryRequest("food")))
                .isInstanceOf(CategoryNameTakenException.class);

        verify(categories, never()).saveAndFlush(any());
    }

    @Test
    void createTranslatesTheUniqueIndexViolationToNameTaken() {
        when(categories.saveAndFlush(any())).thenThrow(TestConstraintViolations.translated("uk_categories_user_name"));

        assertThatThrownBy(() -> service.create(userId, new CategoryRequest("Pets")))
                .isInstanceOf(CategoryNameTakenException.class)
                .hasMessageNotContaining("Pets");
    }

    @Test
    void createDoesNotHideOtherIntegrityViolations() {
        var other = TestConstraintViolations.translated("ck_categories_name_trimmed");
        when(categories.saveAndFlush(any())).thenThrow(other);

        assertThatThrownBy(() -> service.create(userId, new CategoryRequest("Pets"))).isSameAs(other);
    }

    @Test
    void renameChangesTheNameOfAnOwnCategory() {
        var own = Category.createOwn(userId, "Pets", NOW);
        when(categories.findVisibleById(own.getId(), userId)).thenReturn(Optional.of(own));

        var result = service.rename(userId, own.getId(), new CategoryRequest("Pet care"));

        assertThat(own.getName()).isEqualTo("Pet care");
        assertThat(result.name()).isEqualTo("Pet care");
        verify(categories).saveAndFlush(own);
    }

    @Test
    void renameOfADefaultCategoryIsForbidden() {
        var id = UUID.randomUUID();
        when(categories.findVisibleById(id, userId)).thenReturn(Optional.of(defaultCategory()));

        assertThatThrownBy(() -> service.rename(userId, id, new CategoryRequest("Mine")))
                .isInstanceOf(DefaultCategoryReadOnlyException.class);
    }

    @Test
    void renameOfACategoryTheUserCannotSeeIsNotFound() {
        var id = UUID.randomUUID();
        when(categories.findVisibleById(id, userId)).thenReturn(Optional.empty());

        assertThatThrownBy(() -> service.rename(userId, id, new CategoryRequest("Mine")))
                .isInstanceOf(NotFoundException.class);
    }

    @Test
    void renameToADefaultNameIsNameTaken() {
        var own = Category.createOwn(userId, "Pets", NOW);
        when(categories.findVisibleById(own.getId(), userId)).thenReturn(Optional.of(own));
        when(categories.existsDefaultNamedIgnoreCase("Food")).thenReturn(true);

        assertThatThrownBy(() -> service.rename(userId, own.getId(), new CategoryRequest("Food")))
                .isInstanceOf(CategoryNameTakenException.class);
        assertThat(own.getName()).isEqualTo("Pets");
    }

    @Test
    void renameTranslatesTheUniqueIndexViolationToNameTaken() {
        var own = Category.createOwn(userId, "Pets", NOW);
        when(categories.findVisibleById(own.getId(), userId)).thenReturn(Optional.of(own));
        when(categories.saveAndFlush(any())).thenThrow(TestConstraintViolations.translated("uk_categories_user_name"));

        assertThatThrownBy(() -> service.rename(userId, own.getId(), new CategoryRequest("Gym")))
                .isInstanceOf(CategoryNameTakenException.class);
    }

    @Test
    void renameOfARowDeletedMeanwhileIsNotFound() {
        var own = Category.createOwn(userId, "Pets", NOW);
        when(categories.findVisibleById(own.getId(), userId)).thenReturn(Optional.of(own));
        when(categories.saveAndFlush(any())).thenThrow(new ObjectOptimisticLockingFailureException(Category.class, own.getId()));

        assertThatThrownBy(() -> service.rename(userId, own.getId(), new CategoryRequest("Gym")))
                .isInstanceOf(NotFoundException.class);
    }

    @Test
    void deleteOfARowDeletedMeanwhileIsNotFound() {
        var own = Category.createOwn(userId, "Pets", NOW);
        when(categories.findVisibleById(own.getId(), userId)).thenReturn(Optional.of(own));
        doThrow(new ObjectOptimisticLockingFailureException(Category.class, own.getId())).when(categories).flush();

        assertThatThrownBy(() -> service.delete(userId, own.getId())).isInstanceOf(NotFoundException.class);
    }

    @Test
    void deleteRemovesAnOwnCategoryAndFlushesSoTheForeignKeyIsCheckedNow() {
        var own = Category.createOwn(userId, "Pets", NOW);
        when(categories.findVisibleById(own.getId(), userId)).thenReturn(Optional.of(own));

        service.delete(userId, own.getId());

        verify(categories).delete(own);
        verify(categories).flush();
    }

    @Test
    void deleteOfADefaultCategoryIsForbiddenAndDeletesNothing() {
        var id = UUID.randomUUID();
        when(categories.findVisibleById(id, userId)).thenReturn(Optional.of(defaultCategory()));

        assertThatThrownBy(() -> service.delete(userId, id)).isInstanceOf(DefaultCategoryReadOnlyException.class);

        verify(categories, never()).delete(any());
    }

    @Test
    void deleteOfACategoryTheUserCannotSeeIsNotFound() {
        var id = UUID.randomUUID();
        when(categories.findVisibleById(id, userId)).thenReturn(Optional.empty());

        assertThatThrownBy(() -> service.delete(userId, id)).isInstanceOf(NotFoundException.class);
    }

    @Test
    void deleteOfACategoryWithExpensesIsInUse() {
        var own = Category.createOwn(userId, "Pets", NOW);
        when(categories.findVisibleById(own.getId(), userId)).thenReturn(Optional.of(own));
        doThrow(TestConstraintViolations.translated("fk_expenses_categories")).when(categories).flush();

        assertThatThrownBy(() -> service.delete(userId, own.getId())).isInstanceOf(CategoryInUseException.class);
    }

    @Test
    void deleteDoesNotHideOtherIntegrityViolations() {
        var own = Category.createOwn(userId, "Pets", NOW);
        when(categories.findVisibleById(own.getId(), userId)).thenReturn(Optional.of(own));
        doThrow(new DataIntegrityViolationException("other")).when(categories).flush();

        assertThatThrownBy(() -> service.delete(userId, own.getId())).isInstanceOf(DataIntegrityViolationException.class);
    }

    @Test
    void requireVisibleReturnsTheCategoryOrNotFound() {
        var own = Category.createOwn(userId, "Pets", NOW);
        when(categories.findVisibleById(own.getId(), userId)).thenReturn(Optional.of(own));
        var missing = UUID.randomUUID();
        when(categories.findVisibleById(missing, userId)).thenReturn(Optional.empty());

        assertThat(service.requireVisible(userId, own.getId())).isSameAs(own);
        assertThatThrownBy(() -> service.requireVisible(userId, missing)).isInstanceOf(NotFoundException.class);
    }

    // Only a migration creates a default (no user id), so the test uses the constructor reserved for JPA.
    // PT: Só uma migration cria uma padrão (sem user id), então o teste usa o construtor reservado ao JPA.
    private static Category defaultCategory() {
        try {
            var constructor = Category.class.getDeclaredConstructor();
            constructor.setAccessible(true);
            return constructor.newInstance();
        } catch (ReflectiveOperationException e) {
            throw new IllegalStateException(e);
        }
    }
}
