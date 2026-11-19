package com.yulehohenfeld.snapledger.category.service;

import java.time.Clock;
import java.util.List;
import java.util.UUID;

import lombok.RequiredArgsConstructor;

import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.orm.ObjectOptimisticLockingFailureException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import com.yulehohenfeld.snapledger.category.dto.CategoryRequest;
import com.yulehohenfeld.snapledger.category.dto.CategoryResponse;
import com.yulehohenfeld.snapledger.category.entity.Category;
import com.yulehohenfeld.snapledger.category.mapper.CategoryMapper;
import com.yulehohenfeld.snapledger.category.repository.CategoryRepository;
import com.yulehohenfeld.snapledger.shared.error.CategoryInUseException;
import com.yulehohenfeld.snapledger.shared.error.CategoryNameTakenException;
import com.yulehohenfeld.snapledger.shared.error.ConstraintViolations;
import com.yulehohenfeld.snapledger.shared.error.DefaultCategoryReadOnlyException;
import com.yulehohenfeld.snapledger.shared.error.NotFoundException;

/**
 * Categories; the expense feature reaches them only through this class.
 *
 * <p>PT: Categorias; a feature de despesas chega a elas só por esta classe.
 * Notes: docs/code-notes/category.md#categoryservice
 */
@Service
@RequiredArgsConstructor
public class CategoryService {

    static final String NAME_CONSTRAINT = "uk_categories_user_name";
    static final String IN_USE_CONSTRAINT = "fk_expenses_categories";

    private final CategoryRepository categories;
    private final CategoryMapper mapper;
    private final Clock clock;

    /** Defaults first, then the user's own, each group by name. PT: Padrão primeiro, depois as do usuário, cada grupo por nome. */
    @Transactional(readOnly = true)
    public List<CategoryResponse> list(UUID userId) {
        return categories.findVisible(userId).stream().map(mapper::toResponse).toList();
    }

    /**
     * Inserts the category now; a taken name throws CategoryNameTakenException.
     *
     * <p>PT: Insere a categoria agora; um nome já usado lança CategoryNameTakenException.
     * Notes: docs/code-notes/category.md#uniqueness
     */
    @Transactional
    public CategoryResponse create(UUID userId, CategoryRequest request) {
        rejectDefaultNameClash(request.name());
        var category = Category.createOwn(userId, request.name(), clock.instant());
        saveRecognizingTakenName(category);
        return mapper.toResponse(category);
    }

    /** Renames an own category; a default one is 403, another user's is 404. PT: Renomeia uma própria; padrão é 403, de outro usuário é 404. */
    @Transactional
    public CategoryResponse rename(UUID userId, UUID id, CategoryRequest request) {
        var category = requireVisible(userId, id);
        rejectIfDefault(category);
        rejectDefaultNameClash(request.name());
        category.rename(request.name());
        saveRecognizingTakenName(category);
        return mapper.toResponse(category);
    }

    /**
     * Deletes an own category; one that still has expenses throws CategoryInUseException.
     *
     * <p>PT: Apaga uma categoria própria; uma que ainda tem despesas lança CategoryInUseException.
     * Notes: docs/code-notes/category.md#delete
     */
    @Transactional
    public void delete(UUID userId, UUID id) {
        var category = requireVisible(userId, id);
        rejectIfDefault(category);
        try {
            categories.delete(category);
            categories.flush();
        } catch (DataIntegrityViolationException e) {
            if (ConstraintViolations.violates(e, IN_USE_CONSTRAINT)) {
                throw new CategoryInUseException();
            }
            throw e;
        } catch (ObjectOptimisticLockingFailureException e) {
            throw rowGone();
        }
    }

    /**
     * The category when it is a default or the user's own; anything else is 404, identical to
     * "does not exist". Used by the expense feature for every category id it receives.
     *
     * <p>PT: A categoria quando é padrão ou do usuário; qualquer outra é 404, igual a "não existe".
     * Usada pela feature de despesas para todo id de categoria que ela recebe.
     */
    @Transactional(readOnly = true)
    public Category requireVisible(UUID userId, UUID id) {
        return categories.findVisibleById(id, userId).orElseThrow(NotFoundException::new);
    }

    private static void rejectIfDefault(Category category) {
        if (category.isDefault()) {
            throw new DefaultCategoryReadOnlyException();
        }
    }

    // Checked here, not by an index: defaults change only by migration, so no request can race it.
    // PT: Conferido aqui, não por índice: as padrão mudam só por migration, então nenhuma requisição compete.
    // Notes: docs/code-notes/category.md#default-name-clash
    private void rejectDefaultNameClash(String name) {
        if (categories.existsDefaultNamedIgnoreCase(name)) {
            throw new CategoryNameTakenException();
        }
    }

    private void saveRecognizingTakenName(Category category) {
        try {
            categories.saveAndFlush(category);
        } catch (DataIntegrityViolationException e) {
            if (ConstraintViolations.violates(e, NAME_CONSTRAINT)) {
                throw new CategoryNameTakenException();
            }
            throw e;
        } catch (ObjectOptimisticLockingFailureException e) {
            throw rowGone();
        }
    }

    // Without @Version this exception means only "0 rows updated/deleted": another transaction
    // deleted the row after we loaded it. That is "does not exist", so 404, never 500.
    // PT: Sem @Version esta exceção só significa "0 linhas": outra transação apagou a linha depois
    // de carregarmos. Isso é "não existe", então 404, nunca 500.
    // Notes: docs/code-notes/category.md#categoryservice
    private static NotFoundException rowGone() {
        return new NotFoundException();
    }
}
