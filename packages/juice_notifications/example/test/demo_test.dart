import 'package:flutter_test/flutter_test.dart';

import 'package:juice_notifications_example/main.dart';

void main() {
  testWidgets('app can be instantiated', (tester) async {
    expect(const DemoApp(), isA<DemoApp>());
  });
}
