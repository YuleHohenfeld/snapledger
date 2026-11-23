import 'package:flutter/foundation.dart';
import 'package:snapledger/core/api/api_failure.dart';
import 'package:snapledger/features/categories/_shared/data/models/category_model.dart';
import 'package:snapledger/features/categories/_shared/data/models/category_request.dart';
import 'package:snapledger/features/categories/_shared/data/repositories/category_repository.dart';
import 'package:snapledger/features/expenses/_shared/data/models/expense_model.dart';
import 'package:snapledger/features/expenses/_shared/data/models/expense_request.dart';
import 'package:snapledger/features/expenses/_shared/data/repositories/expense_repository.dart';
import 'package:snapledger/features/profile/_shared/data/repositories/user_repository.dart';

/// What the expense form shows; the View draws it and never sees a message string.
/// PT: O que o formulário de gasto mostra; a View o desenha e nunca recebe uma string de mensagem.
/// Notes: docs/code-notes/app-expenses.md#expenseformviewmodel
@immutable
sealed class ExpenseFormState {
  const ExpenseFormState();
}

final class ExpenseFormLoading extends ExpenseFormState {
  const ExpenseFormLoading();
}

/// The expense to edit does not exist (deleted elsewhere, or a link with a bad id).
/// PT: O gasto a editar não existe (apagado em outro lugar, ou um link com id ruim).
final class ExpenseFormNotFound extends ExpenseFormState {
  const ExpenseFormNotFound();
}

final class ExpenseFormFailed extends ExpenseFormState {
  const ExpenseFormFailed(this.failure);

  final ApiFailure failure;
}

final class ExpenseFormEditing extends ExpenseFormState {
  const ExpenseFormEditing({
    required this.categories,
    required this.currency,
    this.initial,
    this.saving = false,
    this.creatingCategory = false,
    this.failure,
    this.categoryFailure,
  });

  /// The user's own categories first (by name), then the defaults in the server's order.
  /// PT: As categorias do próprio usuário primeiro (por nome), depois as padrão na ordem do servidor.
  final List<CategoryModel> categories;

  /// ISO 4217 code of the user's currency: the amount field and its preview use it.
  /// PT: Código ISO 4217 da moeda do usuário: o campo de valor e a prévia dele a usam.
  final String currency;

  /// The expense being edited as the server has it; null when creating.
  /// PT: O gasto sendo editado como o servidor o tem; nulo ao criar.
  final ExpenseModel? initial;

  /// True while a save or delete is in flight: the buttons are off, a second tap does nothing.
  /// PT: Verdadeiro enquanto um salvar ou apagar está em andamento: os botões ficam desligados, um segundo toque nada faz.
  final bool saving;

  /// True while the inline "New category" request is in flight.
  /// PT: Verdadeiro enquanto a requisição do "Nova categoria" embutido está em andamento.
  final bool creatingCategory;

  /// The last save or delete that failed, typed: the View maps it to fields or a banner.
  /// PT: O último salvar ou apagar que falhou, tipado: a View o mapeia para campos ou um banner.
  final ApiFailure? failure;

  /// The last inline category creation that failed (name taken, invalid name...).
  /// PT: A última criação embutida de categoria que falhou (nome repetido, nome inválido...).
  final ApiFailure? categoryFailure;

  ExpenseFormEditing copyWith({
    List<CategoryModel>? categories,
    bool? saving,
    bool? creatingCategory,
    ApiFailure? failure,
    bool clearFailure = false,
    ApiFailure? categoryFailure,
    bool clearCategoryFailure = false,
  }) => ExpenseFormEditing(
    categories: categories ?? this.categories,
    currency: currency,
    initial: initial,
    saving: saving ?? this.saving,
    creatingCategory: creatingCategory ?? this.creatingCategory,
    failure: clearFailure ? null : (failure ?? this.failure),
    categoryFailure: clearCategoryFailure ? null : (categoryFailure ?? this.categoryFailure),
  );
}

/// The save worked. [form] is the form as it was (still busy), so the screen does not flash while it closes.
/// PT: O salvar deu certo. [form] é o formulário como estava (ainda ocupado), para a tela não piscar enquanto fecha.
final class ExpenseFormSaved extends ExpenseFormState {
  const ExpenseFormSaved(this.form);

  final ExpenseFormEditing form;
}

/// The delete worked; [form] as in [ExpenseFormSaved].
/// PT: O apagar deu certo; [form] como em [ExpenseFormSaved].
final class ExpenseFormDeleted extends ExpenseFormState {
  const ExpenseFormDeleted(this.form);

  final ExpenseFormEditing form;
}

/// Business state of the expense form (create when [expenseId] is null, else edit): loads what the form
/// needs, saves, deletes and creates a category on the spot.
/// PT: Estado de negócio do formulário de gasto (criar quando [expenseId] é nulo, senão editar): carrega o que o
/// PT: formulário precisa, salva, apaga e cria uma categoria na hora.
/// Notes: docs/code-notes/app-expenses.md#expenseformviewmodel
class ExpenseFormViewModel extends ChangeNotifier {
  ExpenseFormViewModel({
    required this._expenses,
    required this._categories,
    required this._users,
    this._expenseId,
  });

  final ExpenseRepository _expenses;
  final CategoryRepository _categories;
  final UserRepository _users;
  final String? _expenseId;

  ExpenseFormState _state = const ExpenseFormLoading();
  bool _disposed = false;

  ExpenseFormState get state => _state;

  /// First load, or "try again" after a failed one. Editing loads the expense by id (deep links work).
  /// PT: Primeira carga, ou "tentar de novo" após uma que falhou. Editar carrega o gasto pelo id (deep links funcionam).
  Future<void> load() async {
    if (_disposed) return;
    // Already loading on the first call (from initState): no notify during build.
    // PT: Já está carregando na primeira chamada (do initState): sem notify durante o build.
    if (_state is! ExpenseFormLoading) _emit(const ExpenseFormLoading());
    final id = _expenseId;
    try {
      final results = await Future.wait<Object?>([
        _categories.list(),
        _users.fetchCurrent().then((user) => user.currency),
        if (id != null) _expenses.get(id),
      ]);
      _emit(
        ExpenseFormEditing(
          categories: _ordered(results[0]! as List<CategoryModel>),
          currency: results[1]! as String,
          initial: id == null ? null : results[2]! as ExpenseModel,
        ),
      );
    } on ApiFailure catch (failure) {
      // A malformed id is a 400: for the user it is the same as "no such expense".
      // PT: Um id malformado é um 400: para o usuário é o mesmo que "esse gasto não existe".
      _emit(id != null && _isGone(failure) ? const ExpenseFormNotFound() : ExpenseFormFailed(failure));
    }
  }

  /// Creates or replaces the expense; false when it failed or a save is already running.
  /// PT: Cria ou substitui o gasto; falso quando falhou ou um salvar já está em andamento.
  Future<bool> save(ExpenseRequest request) async {
    final current = _state;
    // The flag is set before the first await: a double tap finds it on and does nothing.
    // PT: A flag é ligada antes do primeiro await: um toque duplo a encontra ligada e nada faz.
    if (current is! ExpenseFormEditing || current.saving || current.creatingCategory) return false;
    final busy = current.copyWith(saving: true, clearFailure: true);
    _emit(busy);
    final id = _expenseId;
    try {
      if (id == null) {
        await _expenses.create(request);
      } else {
        await _expenses.update(id, request);
      }
      _emit(ExpenseFormSaved(busy));
      return true;
    } on ApiFailure catch (failure) {
      _emit(current.copyWith(saving: false, failure: failure));
      return false;
    }
  }

  /// Deletes the expense being edited; false when it failed, there is nothing to delete or a save is running.
  /// PT: Apaga o gasto em edição; falso quando falhou, não há o que apagar ou um salvar está em andamento.
  Future<bool> delete() async {
    final current = _state;
    final id = _expenseId;
    if (id == null || current is! ExpenseFormEditing || current.saving) return false;
    final busy = current.copyWith(saving: true, clearFailure: true);
    _emit(busy);
    try {
      await _expenses.delete(id);
      _emit(ExpenseFormDeleted(busy));
      return true;
    } on ApiFailure catch (failure) {
      _emit(
        failure is ProblemFailure && failure.type == ProblemType.notFound
            ? const ExpenseFormNotFound()
            : current.copyWith(saving: false, failure: failure),
      );
      return false;
    }
  }

  /// Creates an own category from the picker and returns it (already in [ExpenseFormEditing.categories]).
  /// PT: Cria uma categoria própria pelo seletor e a devolve (já em [ExpenseFormEditing.categories]).
  /// Notes: docs/code-notes/app-expenses.md#categorypickersheet
  Future<CategoryModel?> createCategory(String name) async {
    final current = _state;
    if (current is! ExpenseFormEditing || current.creatingCategory || current.saving) return null;
    _emit(current.copyWith(creatingCategory: true, clearCategoryFailure: true));
    try {
      final created = await _categories.create(CategoryRequest(name: name.trim()));
      _emit(
        current.copyWith(
          categories: _ordered([...current.categories, created]),
          creatingCategory: false,
        ),
      );
      return created;
    } on ApiFailure catch (failure) {
      _emit(current.copyWith(creatingCategory: false, categoryFailure: failure));
      return null;
    }
  }

  /// The user edited [field]: its server error goes away, the others stay; a form-level error goes too.
  /// PT: O usuário editou [field]: o erro do servidor dele some, os outros ficam; um erro do formulário some também.
  /// Notes: docs/code-notes/app-expenses.md#expenseformviewmodel
  void clearFieldError(String field) {
    final current = _state;
    if (current is! ExpenseFormEditing) return;
    final failure = current.failure;
    if (failure == null) return;
    if (failure is ProblemFailure && failure.type == ProblemType.validationError) {
      if (!failure.fieldErrors.contains(field)) return;
      final rest = [
        for (final name in failure.fieldErrors)
          if (name != field) name,
      ];
      _emit(
        rest.isEmpty
            ? current.copyWith(clearFailure: true)
            : ExpenseFormEditing(
                categories: current.categories,
                currency: current.currency,
                initial: current.initial,
                saving: current.saving,
                creatingCategory: current.creatingCategory,
                failure: ProblemFailure(
                  status: failure.status,
                  type: failure.type,
                  fieldErrors: rest,
                  errorId: failure.errorId,
                ),
                categoryFailure: current.categoryFailure,
              ),
      );
      return;
    }
    _emit(current.copyWith(clearFailure: true));
  }

  /// The user edited the new category name: its old error goes away.
  /// PT: O usuário editou o nome da nova categoria: o erro antigo some.
  void clearCategoryFailure() {
    final current = _state;
    if (current is ExpenseFormEditing && current.categoryFailure != null) {
      _emit(current.copyWith(clearCategoryFailure: true));
    }
  }

  bool _isGone(ApiFailure failure) =>
      failure is ProblemFailure &&
      (failure.type == ProblemType.notFound || failure.type == ProblemType.validationError);

  // Own categories first, by name without case then id (like the manage screen); defaults keep the server's order.
  // PT: Categorias próprias primeiro, por nome sem diferenciar caixa e depois id (como na tela de gestão); padrões mantêm a ordem do servidor.
  // Notes: docs/code-notes/app-expenses.md#categorypickersheet
  List<CategoryModel> _ordered(Iterable<CategoryModel> all) {
    final own = all.where((c) => !c.isDefault).toList()
      ..sort((a, b) {
        final byName = a.name.toLowerCase().compareTo(b.name.toLowerCase());
        return byName != 0 ? byName : a.id.compareTo(b.id);
      });
    return List.unmodifiable([...own, ...all.where((c) => c.isDefault)]);
  }

  void _emit(ExpenseFormState next) {
    if (_disposed) return;
    _state = next;
    notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    super.dispose();
  }
}
