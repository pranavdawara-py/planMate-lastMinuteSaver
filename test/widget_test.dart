import 'package:flutter_test/flutter_test.dart';
import 'package:planmate/main.dart';

void main() {
  testWidgets('PlanMateApp renders', (WidgetTester tester) async {
    await tester.pumpWidget(const PlanMateApp(showOnboarding: false));
    await tester.pumpAndSettle();
    expect(find.text('planMate'), findsWidgets);
  });
}
