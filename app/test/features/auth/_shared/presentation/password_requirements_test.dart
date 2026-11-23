import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snapledger/core/design/app_theme.dart';
import 'package:snapledger/features/auth/_shared/presentation/password_requirements.dart';
import 'package:snapledger/l10n/gen/app_localizations.dart';

void main() {
  final l10n = lookupAppLocalizations(const Locale('en'));
  late TextEditingController controller;

  setUp(() => controller = TextEditingController());

  tearDown(() => controller.dispose());

  Future<void> pumpChecklist(WidgetTester tester, {ThemeData? theme}) => tester.pumpWidget(
    MaterialApp(
      theme: theme ?? AppTheme.dark(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: PasswordRequirements(controller: controller)),
    ),
  );

  Color? labelColor(WidgetTester tester) =>
      tester.widget<Text>(find.text(l10n.passwordRequirementMinLength(8))).style?.color;

  testWidgets('starts unmet and turns green when the minimum is reached', (tester) async {
    await pumpChecklist(tester);
    final success = SuccessColors.dark.success;
    expect(labelColor(tester), isNot(success));
    expect(find.byIcon(Icons.radio_button_unchecked), findsOneWidget);

    controller.text = 'abcdefgh';
    await tester.pump();

    expect(labelColor(tester), success);
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
  });

  testWidgets('counts bytes: four accented letters are 8 bytes and enough', (tester) async {
    await pumpChecklist(tester);

    controller.text = 'éééé';
    await tester.pump();

    expect(find.byIcon(Icons.check_circle), findsOneWidget);
  });

  testWidgets('goes back to unmet when the password shrinks', (tester) async {
    await pumpChecklist(tester);
    controller.text = 'abcdefgh';
    await tester.pump();

    controller.text = 'abc';
    await tester.pump();

    expect(find.byIcon(Icons.radio_button_unchecked), findsOneWidget);
  });

  testWidgets('uses the dark green in the dark theme', (tester) async {
    await pumpChecklist(tester, theme: AppTheme.dark());

    controller.text = 'abcdefgh';
    await tester.pump();

    expect(labelColor(tester), SuccessColors.dark.success);
  });

  testWidgets('semantics say whether the rule is met', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpChecklist(tester);
    expect(
      find.bySemanticsLabel('${l10n.passwordRequirementMinLength(8)}, ${l10n.requirementNotMet}'),
      findsOneWidget,
    );

    controller.text = 'abcdefgh';
    await tester.pump();

    expect(
      find.bySemanticsLabel('${l10n.passwordRequirementMinLength(8)}, ${l10n.requirementMet}'),
      findsOneWidget,
    );
    handle.dispose();
  });
}
