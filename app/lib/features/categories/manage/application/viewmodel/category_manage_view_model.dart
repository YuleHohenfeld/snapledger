import 'package:flutter/foundation.dart';
import 'package:snapledger/core/api/api_failure.dart';
import 'package:snapledger/features/categories/_shared/data/models/category_model.dart';
import 'package:snapledger/features/categories/_shared/data/models/category_request.dart';
import 'package:snapledger/features/categories/_shared/data/repositories/category_repository.dart';

/// What the category screen shows; the View draws it and never sees a message string.
/// PT: O que a tela de categorias mostra; a View a desenha e nunca recebe uma string de mensagem.
/// Notes: docs/code-notes/app-categories.md#categorymanageviewmodel
@immutable
sealed class CategoryManageState {
  const CategoryManageState();
}

final class CategoryManageLoading extends CategoryManageState {
  const CategoryManageLoading();
}

final class CategoryManageLoaded extends CategoryManageState {
  const CategoryManageLoaded({
    required this.defaults,
    required this.own,
    this.busy = false,
    this.failure,
  });

  /// The read-only categories every user has, in the server's order.
  /// PT: As categorias somente leitura que todo usuário tem, na ordem do servidor.
  final List<CategoryModel> defaults;

  /// The categories the user created, ordered by name.
  /// PT: As categorias que o usuário criou, ordenadas por nome.
  final List<CategoryModel> own;

  /// True while a create, rename or delete is in flight.
  /// PT: Verdadeiro enquanto um criar, renomear ou apagar está em andamento.
  final bool busy;

  /// The last write (or refresh) that failed, kept typed so the View localizes it; the list stays.
  /// PT: A última escrita (ou atualização) que falhou, mantida tipada para a View traduzir; a lista permanece.
  final ApiFailure? failure;

  CategoryManageLoaded copyWith({
    List<CategoryModel>? defaults,
    List<CategoryModel>? own,
    bool? busy,
    ApiFailure? failure,
    bool clearFailure = false,
  }) => CategoryManageLoaded(
    defaults: defaults ?? this.defaults,
    own: own ?? this.own,
    busy: busy ?? this.busy,
    failure: clearFailure ? null : (failure ?? this.failure),
  );
}

final class CategoryManageFailed extends CategoryManageState {
  const CategoryManageFailed(this.failure);

  final ApiFailure failure;
}

/// Business state of the category screen: loads the categories and creates, renames and deletes own ones.
/// PT: Estado de negócio da tela de categorias: carrega as categorias e cria, renomeia e apaga as próprias.
/// Notes: docs/code-notes/app-categories.md#categorymanageviewmodel
class CategoryManageViewModel extends ChangeNotifier {
  CategoryManageViewModel({required this._categories});

  final CategoryRepository _categories;
  CategoryManageState _state = const CategoryManageLoading();
  bool _disposed = false;

  CategoryManageState get state => _state;

  /// First load, or "try again" after a failed one.
  /// PT: Primeira carga, ou "tentar de novo" após uma que falhou.
  Future<void> load() async {
    if (_disposed) return;
    // Already loading on the first call (from initState): no notify during build.
    // PT: Já está carregando na primeira chamada (do initState): sem notify durante o build.
    if (_state is! CategoryManageLoading) _emit(const CategoryManageLoading());
    try {
      _emit(_loaded(await _categories.list()));
    } on ApiFailure catch (failure) {
      _emit(CategoryManageFailed(failure));
    }
  }

  /// Pull to refresh: reloads while keeping the list on screen; a failure is kept next to it.
  /// PT: Puxar para atualizar: recarrega mantendo a lista na tela; uma falha fica junto dela.
  Future<void> refresh() async {
    final current = _state;
    if (current is! CategoryManageLoaded) return load();
    if (current.busy) return;
    // Busy during the refresh too, so a write cannot start from a list that is about to be replaced.
    // PT: Ocupado também durante a atualização, para uma escrita não partir de uma lista que vai ser trocada.
    _emit(current.copyWith(busy: true, clearFailure: true));
    try {
      _emit(_loaded(await _categories.list()));
    } on ApiFailure catch (failure) {
      _emit(current.copyWith(failure: failure));
    }
  }

  /// Creates an own category; false when it failed or another write is still running.
  /// PT: Cria uma categoria própria; falso quando falhou ou outra escrita ainda está em andamento.
  Future<bool> create(String name) => _write((loaded) async {
    final created = await _categories.create(CategoryRequest(name: name.trim()));
    return loaded.copyWith(own: _sorted([...loaded.own, created]));
  });

  /// Renames an own category; an unchanged name succeeds without a request.
  /// PT: Renomeia uma categoria própria; um nome igual tem sucesso sem requisição.
  Future<bool> rename(String id, String name) => _write((loaded) async {
    final trimmed = name.trim();
    if (loaded.own.any((c) => c.id == id && c.name == trimmed)) return loaded;
    final renamed = await _categories.rename(id, CategoryRequest(name: trimmed));
    return loaded.copyWith(own: _sorted([for (final c in loaded.own) c.id == id ? renamed : c]));
  });

  /// Deletes an own category; the server refuses (409) while it still has expenses.
  /// PT: Apaga uma categoria própria; o servidor recusa (409) enquanto ela ainda tem gastos.
  Future<bool> delete(String id) => _write((loaded) async {
    await _categories.delete(id);
    return loaded.copyWith(own: [for (final c in loaded.own) if (c.id != id) c]);
  });

  /// Drops an old failure once the user edits the name or dismisses it.
  /// PT: Descarta uma falha antiga quando o usuário edita o nome ou a dispensa.
  void clearFailure() {
    final current = _state;
    if (current is CategoryManageLoaded && current.failure != null) {
      _emit(current.copyWith(clearFailure: true));
    }
  }

  // One write at a time (double tap, two dialogs): the busy flag is the guard.
  // PT: Uma escrita por vez (toque duplo, dois diálogos): a flag busy é a trava.
  Future<bool> _write(Future<CategoryManageLoaded> Function(CategoryManageLoaded) action) async {
    final current = _state;
    if (current is! CategoryManageLoaded || current.busy) return false;
    final start = current.copyWith(busy: true, clearFailure: true);
    _emit(start);
    try {
      final next = await action(start);
      // The state may only have changed by this write, so building on [current] is safe.
      // PT: O estado só pode ter mudado por esta escrita, então partir de [current] é seguro.
      _emit(next.copyWith(busy: false));
      return true;
    } on ApiFailure catch (failure) {
      _emit(current.copyWith(busy: false, failure: failure));
      // Not found: another device deleted it, so the list is stale. Reload and keep the message.
      // PT: Não encontrada: outro aparelho a apagou, então a lista está velha. Recarrega e mantém a mensagem.
      if (failure is ProblemFailure && failure.type == ProblemType.notFound) {
        await refresh();
        final reloaded = _state;
        if (reloaded is CategoryManageLoaded && reloaded.failure == null) {
          _emit(reloaded.copyWith(failure: failure));
        }
      }
      return false;
    }
  }

  CategoryManageLoaded _loaded(List<CategoryModel> all) => CategoryManageLoaded(
    defaults: List.unmodifiable(all.where((c) => c.isDefault)),
    own: _sorted(all.where((c) => !c.isDefault)),
  );

  // Same order as the server for own categories: name without case, then id (contract).
  // PT: Mesma ordem do servidor para as próprias: nome sem diferenciar caixa, depois id (contrato).
  List<CategoryModel> _sorted(Iterable<CategoryModel> items) {
    final list = items.toList()
      ..sort((a, b) {
        final byName = a.name.toLowerCase().compareTo(b.name.toLowerCase());
        return byName != 0 ? byName : a.id.compareTo(b.id);
      });
    return List.unmodifiable(list);
  }

  void _emit(CategoryManageState next) {
    if (_disposed) return;
    _state = next;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
