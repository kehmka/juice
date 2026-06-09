import 'package:flutter_test/flutter_test.dart';

import 'package:juice_routing_example/main.dart';

void main() {
  testWidgets('routing example boots to the home screen', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    expect(find.text('Home'), findsOneWidget);
    expect(find.text('juice_routing Demo'), findsOneWidget);
  });
}
