import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snapledger/app/shell/application/controller/shell_controller.dart';
import 'package:snapledger/app/shell/application/viewmodel/shell_view_model.dart';
import 'package:snapledger/app/shell/presentation/widgets/shell_top_bar.dart';
import 'package:snapledger/core/design/app_theme.dart';
import 'package:snapledger/l10n/gen/app_localizations.dart';

import '../../../../support/fake_auth_repository.dart';
import '../../../../support/fake_navigator.dart';
import '../../../../support/fake_session_refresher.dart';

void main() {
  const inset = 44.0;

  testWidgets('a top inset adds to the bar and never squeezes its 64px content', (tester) async {
    final session = inMemorySession().session;
    final viewModel = ShellViewModel(auth: FakeAuthRepository(), session: session);
    addTearDown(() {
      viewModel.dispose();
      session.dispose();
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(1280, 800),
            padding: EdgeInsets.only(top: inset),
          ),
          child: Scaffold(
            body: Column(
              children: [
                ShellTopBar(
                  selectedIndex: 0,
                  onTabSelected: (_) {},
                  controller: ShellController(viewModel: viewModel, navigator: FakeNavigator()),
                  loggingOut: false,
                ),
              ],
            ),
          ),
        ),
      ),
    );

    expect(tester.getSize(find.byType(ShellTopBar)).height, ShellTopBar.contentHeight + inset);
    // The tab row keeps its full height below the inset.
    // PT: A linha de abas mantém a altura inteira abaixo do recuo.
    final content = find.descendant(
      of: find.byType(ShellTopBar),
      matching: find.byWidgetPredicate(
        (w) => w is SizedBox && w.height == ShellTopBar.contentHeight,
      ),
    );
    expect(tester.getSize(content.first).height, ShellTopBar.contentHeight);
    expect(tester.getTopLeft(content.first).dy, inset);
  });
}
