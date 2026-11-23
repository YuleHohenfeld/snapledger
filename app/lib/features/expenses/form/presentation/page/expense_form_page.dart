import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:snapledger/core/design/widgets/app_backdrop.dart';
import 'package:snapledger/core/design/widgets/load_error.dart';
import 'package:snapledger/core/design/widgets/responsive_body.dart';
import 'package:snapledger/core/design/window_size.dart';
import 'package:snapledger/core/l10n/failure_messages.dart';
import 'package:snapledger/features/expenses/form/application/controller/expense_form_controller.dart';
import 'package:snapledger/features/expenses/form/application/viewmodel/expense_form_view_model.dart';
import 'package:snapledger/features/expenses/form/presentation/widgets/expense_form_body.dart';
import 'package:snapledger/features/expenses/form/presentation/widgets/expense_not_found.dart';
import 'package:snapledger/l10n/gen/app_localizations.dart';

/// Create (no [expenseId]) or edit an expense; editing loads it by id, so a deep link works.
/// PT: Criar (sem [expenseId]) ou editar um gasto; editar o carrega pelo id, então um deep link funciona.
/// Notes: docs/code-notes/app-expenses.md#expenseformpage
class ExpenseFormPage extends StatelessWidget {
  /// [now] is the clock of "today" (the default day and the date limits); tests pass a fixed one.
  /// PT: [now] é o relógio de "hoje" (o dia padrão e os limites de data); os testes passam um fixo.
  const ExpenseFormPage({super.key, this.expenseId, this.now = DateTime.now});

  final String? expenseId;
  final DateTime Function() now;

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
    create: (context) => ExpenseFormViewModel(
      expenses: context.read(),
      categories: context.read(),
      users: context.read(),
      expenseId: expenseId,
    ),
    child: _ExpenseFormView(expenseId: expenseId, now: now),
  );
}

class _ExpenseFormView extends StatefulWidget {
  const _ExpenseFormView({required this.expenseId, required this.now});

  final String? expenseId;
  final DateTime Function() now;

  @override
  State<_ExpenseFormView> createState() => _ExpenseFormViewState();
}

class _ExpenseFormViewState extends State<_ExpenseFormView> {
  ExpenseFormController? _controller;

  // Created here, not in initState: the controller needs the locale, and Localizations is not readable yet there.
  // PT: Criado aqui, não no initState: o controller precisa do locale, e o Localizations ainda não é legível lá.
  // Notes: docs/code-notes/app-expenses.md#expenseformcontroller
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _controller ??= ExpenseFormController(
      viewModel: context.read<ExpenseFormViewModel>(),
      navigator: context.read(),
      now: widget.now,
      locale: Localizations.localeOf(context).toString(),
    )..start();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _onDelete(ExpenseFormController controller) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.expenseFormDeleteTitle),
        content: Text(l10n.expenseFormDeleteBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.expenseFormCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.expenseFormDeleteConfirm),
          ),
        ],
      ),
    );
    if (confirmed ?? false) await controller.onDeleteConfirmed();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final controller = _controller!;
    final state = context.select((ExpenseFormViewModel vm) => vm.state);
    final editing = widget.expenseId != null;
    // While the screen closes (Saved, Deleted) the same form stays, so the delete icon does not vanish.
    // PT: Enquanto a tela fecha (Saved, Deleted) o mesmo formulário fica, então o ícone de apagar não some.
    final form = switch (state) {
      ExpenseFormEditing() => state,
      ExpenseFormSaved(:final form) || ExpenseFormDeleted(:final form) => form,
      _ => null,
    };
    // A pushed page: its own backdrop (opaque base) so the list under it never shows during the transition.
    // PT: Uma página empilhada: o próprio fundo (base opaca) para a lista de baixo não aparecer na transição.
    return AppBackdrop(
      animated: false,
      child: Scaffold(
        appBar: AppBar(
          title: Text(editing ? l10n.expenseFormEditTitle : l10n.expenseFormNewTitle),
          actions: [
            if (editing && form != null)
              IconButton(
                tooltip: l10n.expenseFormDelete,
                icon: const Icon(Icons.delete_outline),
                onPressed: form.saving || form.creatingCategory
                    ? null
                    : () => unawaited(_onDelete(controller)),
              ),
          ],
        ),
        body: SafeArea(
          child: ResponsiveBody(
            maxWidth: AppBreakpoints.contentWidth,
            child: switch (state) {
              ExpenseFormLoading() => const Center(child: CircularProgressIndicator()),
              // Closing: the same form, still busy, until the route is gone.
              // PT: Fechando: o mesmo formulário, ainda ocupado, até a rota sumir.
              ExpenseFormSaved(:final form) || ExpenseFormDeleted(:final form) => ExpenseFormBody(
                state: form,
                controller: controller,
              ),
              ExpenseFormNotFound() => ExpenseNotFound(onBack: controller.onBackTapped),
              ExpenseFormFailed(:final failure) => LoadError(
                message: failureMessage(l10n, failure) ?? l10n.errorUnexpected,
                retryLabel: l10n.expenseListRetry,
                onRetry: controller.onRetryTapped,
              ),
              ExpenseFormEditing() => ExpenseFormBody(state: state, controller: controller),
            },
          ),
        ),
      ),
    );
  }
}
