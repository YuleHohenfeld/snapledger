import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snapledger/features/expenses/list/presentation/widgets/expense_list_header.dart';
import 'package:snapledger/l10n/gen/app_localizations.dart';

import '../../../../../support/pump_app.dart';

void main() {
  final l10n = lookupAppLocalizations(const Locale('en'));

  testWidgets('shows the title and the New expense button, which calls onNewTapped', (
    tester,
  ) async {
    var taps = 0;
    await pumpApp(tester, Scaffold(body: ExpenseListHeader(onNewTapped: () => taps++)));

    expect(find.text(l10n.expensesTitle), findsOneWidget);

    await tester.tap(find.text(l10n.expenseListNew));

    expect(taps, 1);
  });
}
