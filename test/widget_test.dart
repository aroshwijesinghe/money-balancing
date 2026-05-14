import 'package:flutter_test/flutter_test.dart';

import 'package:boarding_money_app/main.dart';

void main() {
  testWidgets('App builds', (WidgetTester tester) async {
    await tester.pumpWidget(const BoardingMoneyApp());
    expect(find.byType(PinGate), findsOneWidget);
  });
}
