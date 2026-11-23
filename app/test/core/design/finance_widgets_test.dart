import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snapledger/core/design/widgets/empty_state.dart';
import 'package:snapledger/core/design/widgets/money_field.dart';
import 'package:snapledger/core/design/widgets/month_selector.dart';
import 'package:snapledger/core/time/month.dart';
import 'package:snapledger/l10n/gen/app_localizations.dart';

import '../../support/pump_app.dart';

void main() {
  final l10n = lookupAppLocalizations(const Locale('en'));

  group('MoneyInputFormatter', () {
    final dot = MoneyInputFormatter(locale: 'en', decimals: 2);
    final comma = MoneyInputFormatter(locale: 'pt_BR', decimals: 2);

    String type(MoneyInputFormatter formatter, String before, String after) => formatter
        .formatEditUpdate(
          TextEditingValue(text: before, selection: TextSelection.collapsed(offset: before.length)),
          TextEditingValue(text: after, selection: TextSelection.collapsed(offset: after.length)),
        )
        .text;

    test('lets digits and one separator in, at most two decimals', () {
      expect(type(dot, '12', '12.'), '12.');
      expect(type(dot, '12.5', '12.50'), '12.50');
      expect(type(dot, '12.50', '12.509'), '12.50');
    });

    test('rejects a second separator, letters and signs', () {
      expect(type(dot, '12.5', '12.5.'), '12.5');
      expect(type(dot, '12', '12a'), '12');
      expect(type(dot, '12', '-12'), '12');
    });

    test('a typed foreign separator becomes the locale one (regression: 4,2,.,9,0 was 4290)', () {
      expect(type(comma, '42', '42.'), '42,');
      expect(type(dot, '42', '42,'), '42.');
      expect(type(comma, '4', '4.'), '4,');
      expect(type(comma, '', '.'), ',');
    });

    test('a single separator key is refused when one is already there', () {
      expect(type(comma, '4,2', '4,2.'), '4,2');
      expect(type(dot, '4.2', '4.2,'), '4.2');
    });

    test('a paste is refused, never altered (regression: 42.90 in pt_BR was 4290)', () {
      expect(type(comma, '', '42.90'), '');
      expect(type(dot, '', '42,90'), '');
      expect(type(dot, '', '12.509'), '');
      expect(type(dot, '', '12abc'), '');
    });

    test('a pasted amount in exact 3-digit groups is normalized to the plain locale form', () {
      expect(type(comma, '', '1.234,50'), '1234,50');
      expect(type(dot, '', '1,234.50'), '1234.50');
    });

    test('a currency with no decimals refuses a separator key and a decimal paste', () {
      final none = MoneyInputFormatter(locale: 'en', decimals: 0);

      expect(type(none, '15', '15.'), '15');
      expect(type(none, '15', '15,'), '15');
      expect(type(none, '', '1.50'), '');
    });
  });

  group('MoneyField', () {
    testWidgets('shows the currency symbol and filters what is typed', (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await pumpApp(
        tester,
        Scaffold(
          body: MoneyField(controller: controller, label: 'Amount', currency: 'USD'),
        ),
      );

      expect(find.text('\$ '), findsOneWidget);
      await tester.enterText(find.byType(TextFormField), '12.34');
      await tester.enterText(find.byType(TextFormField), '12.345abc');

      expect(controller.text, '12.34');
    });

    testWidgets('uses a decimal keyboard, or an integer one for JPY', (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      TextInputType keyboard() => tester.widget<TextField>(find.byType(TextField)).keyboardType;

      await pumpApp(
        tester,
        Scaffold(body: MoneyField(controller: controller, label: 'Amount', currency: 'BRL')),
      );
      expect(keyboard().decimal, isTrue);

      await pumpApp(
        tester,
        Scaffold(body: MoneyField(controller: controller, label: 'Amount', currency: 'JPY')),
      );
      expect(keyboard().decimal, isFalse);
    });

    testWidgets('announces the currency to screen readers', (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await pumpApp(
        tester,
        Scaffold(body: MoneyField(controller: controller, label: 'Amount', currency: 'BRL')),
      );

      expect(
        find.byWidgetPredicate(
          (w) => w is Semantics && w.properties.hint == l10n.moneyFieldCurrencyHint('BRL'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('a validator error vanishes on the first edit (AppTextField behavior)', (tester) async {
      final controller = TextEditingController();
      final formKey = GlobalKey<FormState>();
      addTearDown(controller.dispose);
      await pumpApp(
        tester,
        Scaffold(
          body: Form(
            key: formKey,
            child: MoneyField(
              controller: controller,
              label: 'Amount',
              currency: 'USD',
              validator: (_) => 'bad amount',
            ),
          ),
        ),
      );

      formKey.currentState!.validate();
      await tester.pump();
      expect(find.text('bad amount'), findsOneWidget);

      await tester.enterText(find.byType(TextFormField), '1');
      await tester.pump();

      expect(find.text('bad amount'), findsNothing);
    });
  });

  group('MonthSelector', () {
    testWidgets('shows the month and reports taps on both arrows', (tester) async {
      var previous = 0;
      var next = 0;
      await pumpApp(
        tester,
        Scaffold(
          body: MonthSelector(
            month: const Month(2026, 11),
            onPrevious: () => previous++,
            onNext: () => next++,
          ),
        ),
      );

      expect(find.text('November 2026'), findsOneWidget);
      await tester.tap(find.byTooltip(l10n.monthSelectorPrevious));
      await tester.tap(find.byTooltip(l10n.monthSelectorNext));

      expect((previous, next), (1, 1));
    });

    testWidgets('next is disabled when canGoNext is false', (tester) async {
      var next = 0;
      await pumpApp(
        tester,
        Scaffold(
          body: MonthSelector(
            month: const Month(2026, 11),
            onPrevious: () {},
            onNext: () => next++,
            canGoNext: false,
          ),
        ),
      );

      await tester.tap(find.byTooltip(l10n.monthSelectorNext), warnIfMissed: false);

      expect(next, 0);
      expect(find.byTooltip(l10n.monthSelectorPrevious), findsOneWidget);
    });
  });

  group('EmptyState', () {
    testWidgets('shows the headline, the help line and the action', (tester) async {
      var taps = 0;
      await pumpApp(
        tester,
        Scaffold(
          body: EmptyState(
            icon: Icons.receipt_long_outlined,
            title: 'Nothing here',
            body: 'Add your first one',
            action: TextButton(onPressed: () => taps++, child: const Text('Add')),
          ),
        ),
      );

      expect(find.text('Nothing here'), findsOneWidget);
      expect(find.text('Add your first one'), findsOneWidget);
      await tester.tap(find.text('Add'));
      expect(taps, 1);
    });

    testWidgets('works without an action', (tester) async {
      await pumpApp(
        tester,
        const Scaffold(body: EmptyState(icon: Icons.inbox, title: 'T', body: 'B')),
      );

      expect(find.byType(TextButton), findsNothing);
    });
  });
}
