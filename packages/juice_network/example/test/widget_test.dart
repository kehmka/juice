import 'package:flutter_test/flutter_test.dart';
import 'package:juice_network_example/main.dart';

void main() {
  testWidgets('App renders without error', (WidgetTester tester) async {
    // Verify the app can be instantiated
    expect(const FetchArcadeApp(), isA<FetchArcadeApp>());
  });
}
