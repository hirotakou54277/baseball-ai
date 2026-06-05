import 'package:flutter_test/flutter_test.dart';
import 'package:baseball_ai_app/main.dart';

void main() {
  testWidgets('App starts smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const BaseballAiApp());
    expect(find.byType(BaseballAiApp), findsOneWidget);
  });
}
