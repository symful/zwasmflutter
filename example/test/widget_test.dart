import 'package:flutter_test/flutter_test.dart';
import 'package:zwasm_example/main.dart';

void main() {
  testWidgets('demo renders', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());
    expect(find.text('zwasm Flutter demo'), findsOneWidget);
    expect(find.text('Run'), findsOneWidget);
  });
}
