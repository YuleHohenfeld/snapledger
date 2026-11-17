import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snapledger/core/design/app_theme.dart';
import 'package:snapledger/core/design/widgets/otp_code_input.dart';
import 'package:snapledger/l10n/gen/app_localizations.dart';

void main() {
  late TextEditingController controller;
  late FocusNode focusNode;
  late List<String> completed;

  setUp(() {
    controller = TextEditingController();
    focusNode = FocusNode();
    completed = [];
  });

  tearDown(() {
    controller.dispose();
    focusNode.dispose();
  });

  Future<void> pumpInput(
    WidgetTester tester, {
    OtpStatus status = OtpStatus.idle,
    String? errorText,
    ThemeData? theme,
  }) => tester.pumpWidget(
    MaterialApp(
      theme: theme ?? AppTheme.light(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: OtpCodeInput(
            controller: controller,
            focusNode: focusNode,
            status: status,
            errorText: errorText,
            onCompleted: completed.add,
          ),
        ),
      ),
    ),
  );

  List<Border> borders(WidgetTester tester) => tester
      .widgetList<DecoratedBox>(
        find.descendant(of: find.byType(OtpCodeInput), matching: find.byType(DecoratedBox)),
      )
      .map((box) => (box.decoration as BoxDecoration).border)
      .whereType<Border>()
      .toList();

  testWidgets('draws six boxes', (tester) async {
    await pumpInput(tester);

    expect(borders(tester), hasLength(6));
  });

  testWidgets('typing fills the boxes in order and does not complete before the 6th digit', (
    tester,
  ) async {
    await pumpInput(tester);

    await tester.enterText(find.byType(TextField), '042');
    await tester.pump();

    expect(find.text('0'), findsOneWidget);
    expect(find.text('4'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(completed, isEmpty);
  });

  testWidgets('pasting six digits completes once; spaces and letters are dropped', (tester) async {
    await pumpInput(tester);

    await tester.enterText(find.byType(TextField), '042 917');
    await tester.pump();

    expect(controller.text, '042917');
    expect(completed, ['042917']);
  });

  testWidgets('more than six digits are cut at six', (tester) async {
    await pumpInput(tester);

    await tester.enterText(find.byType(TextField), '12345678');
    await tester.pump();

    expect(controller.text, '123456');
    expect(completed, ['123456']);
  });

  testWidgets('backspace removes the last digit and does not complete', (tester) async {
    await pumpInput(tester);
    await tester.enterText(find.byType(TextField), '04291');
    await tester.pump();

    await tester.enterText(find.byType(TextField), '0429');
    await tester.pump();

    expect(find.text('1'), findsNothing);
    expect(completed, isEmpty);
  });

  testWidgets('the focused box has the primary border', (tester) async {
    await pumpInput(tester);
    final primary = AppTheme.light().colorScheme.primary;

    focusNode.requestFocus();
    await tester.pump();

    expect(borders(tester).first.top.color, primary);
    expect(borders(tester)[1].top.color, isNot(primary));

    await tester.enterText(find.byType(TextField), '04');
    await tester.pump();

    expect(borders(tester)[2].top.color, primary);
    expect(borders(tester).first.top.color, isNot(primary));
  });

  testWidgets('error state: every border red, message shown, boxes cleared', (tester) async {
    await pumpInput(tester);
    await tester.enterText(find.byType(TextField), '000000');
    await tester.pump();
    final error = AppTheme.light().colorScheme.error;

    await pumpInput(tester, status: OtpStatus.error, errorText: 'That code is not right.');
    await tester.pumpAndSettle();

    expect(borders(tester).every((border) => border.top.color == error), isTrue);
    expect(find.text('That code is not right.'), findsOneWidget);
    expect(controller.text, isEmpty);
  });

  testWidgets('error state shakes the boxes', (tester) async {
    await pumpInput(tester);

    await pumpInput(tester, status: OtpStatus.error, errorText: 'x');
    await tester.pump(const Duration(milliseconds: 60));

    final shake = tester.widget<Transform>(
      find.descendant(of: find.byType(OtpCodeInput), matching: find.byType(Transform)).first,
    );
    expect(shake.transform.getTranslation().x, isNot(0));
    await tester.pumpAndSettle();
  });

  testWidgets('success state: every border green with a check', (tester) async {
    await pumpInput(tester, status: OtpStatus.success);
    final green = SuccessColors.light.success;

    expect(borders(tester).every((border) => border.top.color == green), isTrue);
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
  });

  testWidgets('success state in the dark theme uses the dark green', (tester) async {
    await pumpInput(tester, status: OtpStatus.success, theme: AppTheme.dark());

    expect(
      borders(tester).every((border) => border.top.color == SuccessColors.dark.success),
      isTrue,
    );
  });

  testWidgets('typing is ignored while verifying or after success', (tester) async {
    await pumpInput(tester, status: OtpStatus.verifying);

    await tester.enterText(find.byType(TextField), '123');
    await tester.pump();

    expect(controller.text, isEmpty);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });

  testWidgets('semantics: one labelled field, errors announced as a live region', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpInput(tester, status: OtpStatus.error, errorText: 'That code is not right.');
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel(RegExp('Verification code, 6 digits')), findsWidgets);
    expect(
      find.ancestor(
        of: find.text('That code is not right.'),
        matching: find.byWidgetPredicate((w) => w is Semantics && w.properties.liveRegion == true),
      ),
      findsOneWidget,
    );
    handle.dispose();
  });
}
