import 'package:flutter_test/flutter_test.dart';

import 'package:juice_storage_example/main.dart';

void main() {
  testWidgets('StorageArcadeApp builds', (WidgetTester tester) async {
    // Note: This is a basic smoke test. The app requires async initialization
    // of StorageBloc which makes widget testing more involved.
    // Full integration tests should be done separately.
    await tester.pumpWidget(const StorageArcadeApp());
    await tester.pump();
  });
}
