import 'package:juice/juice.dart';
import 'package:juice_storage/juice_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:juice_storage_example/blocs/arcade_demo_bloc.dart';
import 'package:juice_storage_example/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() async {
    await BlocScope.endAll();
  });

  testWidgets('StorageArcadeApp builds', (WidgetTester tester) async {
    if (!BlocScope.isRegistered<StorageBloc>()) {
      BlocScope.register<StorageBloc>(
        () => StorageBloc(
          config: const StorageConfig(
            prefsKeyPrefix: 'arcade_',
            hiveBoxesToOpen: ['arcade_box'],
            sqliteDatabaseName: 'arcade_test.db',
            enableBackgroundCleanup: false,
          ),
        ),
        lifecycle: BlocLifecycle.permanent,
      );
    }

    final storage = BlocScope.get<StorageBloc>();
    await storage.initialize();

    if (!BlocScope.isRegistered<ArcadeDemoBloc>()) {
      BlocScope.register<ArcadeDemoBloc>(
        () => ArcadeDemoBloc(),
        lifecycle: BlocLifecycle.leased,
      );
    }

    await tester.pumpWidget(const StorageArcadeApp());
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Arcade'), findsWidgets);
    expect(find.text('Inspector'), findsWidgets);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }, skip: true);
}
