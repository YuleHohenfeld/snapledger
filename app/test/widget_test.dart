import 'package:flutter_test/flutter_test.dart';
import 'package:snapledger/main.dart';

void main() {
  testWidgets('shows the product name on the placeholder screen', (tester) async {
    await tester.pumpWidget(const SnapLedgerApp());

    expect(find.text(SnapLedgerApp.productName), findsOneWidget);
  });
}
