import 'package:flutter_test/flutter_test.dart';
import 'package:juice/juice.dart';
import '../test_helpers.dart';

void main() {
  group('StatelessJuiceWidget Tests', () {
    setUp(() {
      BlocScope.reset();
    });

    tearDown(() {
      BlocScope.reset();
    });

    testWidgets('StatelessJuiceWidget displays initial state', (tester) async {
      // Register bloc with known initial state
      BlocScope.register<TestBloc>(
        () => TestBloc(initialState: TestState(value: 42)),
        lifecycle: BlocLifecycle.permanent,
      );

      // Build widget using BlocScope
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: TestWidget(),
        ),
      ));

      // Verify initial state is displayed
      expect(find.text('Value: 42'), findsOneWidget);
    });

    testWidgets('StatelessJuiceWidget updates when state changes',
        (tester) async {
      // Register bloc with initial state
      BlocScope.register<TestBloc>(
        () => TestBloc(initialState: TestState(value: 0)),
        lifecycle: BlocLifecycle.permanent,
      );

      // Build widget using BlocScope
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: TestWidget(),
        ),
      ));

      // Verify initial state
      expect(find.text('Value: 0'), findsOneWidget);

      // Update state
      final bloc = BlocScope.get<TestBloc>();
      await bloc.send(TestEvent());
      await tester.pump();

      // Verify updated state is displayed
      expect(find.text('Value: 1'), findsOneWidget);
    });

    testWidgets('Widget rebuilds only for specified groups', (tester) async {
      // Register bloc with initial state
      BlocScope.register<TestBloc>(
        () => TestBloc(initialState: TestState(value: 0)),
        lifecycle: BlocLifecycle.permanent,
      );

      // Track build count
      int buildCount = 0;

      // Build widget with specific group
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: TestWidget(
            groups: const {"specific-group"},
            doOnBuild: () => buildCount++,
          ),
        ),
      ));

      // Initial build
      expect(buildCount, 1);

      // Send event with non-matching group
      final bloc = BlocScope.get<TestBloc>();
      await bloc.send(TestEvent(groups: {"other-group"}));
      await tester.pump();

      // Should not rebuild
      expect(buildCount, 1);

      // Send event with matching group
      await bloc.send(TestEvent(groups: {"specific-group"}));
      await tester.pump();

      // Should rebuild
      expect(buildCount, 2);
    });

    testWidgets('Widget with "*" group rebuilds for all state changes',
        (tester) async {
      // Register bloc with initial state
      BlocScope.register<TestBloc>(
        () => TestBloc(initialState: TestState(value: 0)),
        lifecycle: BlocLifecycle.permanent,
      );

      // Track build count
      int buildCount = 0;

      var widget = MaterialApp(
        home: Scaffold(
          body: TestWidget(
            groups: const {"my-group"},
            doOnBuild: () => buildCount++,
          ),
        ),
      );

      // Build widget with wildcard group
      await tester.pumpWidget(widget);
      expect(buildCount, 1);

      // Send event with specific group
      final bloc = BlocScope.get<TestBloc>();
      await bloc.send(TestEvent(groups: {"*"}));
      await tester.pump();

      expect(buildCount, 2);

      await bloc.send(TestEvent(groups: {"another-group"}));
      await tester.pump();

      expect(buildCount, 2);
    });
  });
}
