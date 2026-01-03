import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice/juice.dart';
import '../test_helpers.dart';

void main() {
  group('StatelessJuiceWidget Tests', () {
    late TestResolver resolver;

    setUp(() {
      resolver = TestResolver();
    });

    tearDown(() async {
      // Clean up blocs between tests
      await resolver.disposeAll();
    });

    testWidgets('StatelessJuiceWidget displays initial state', (tester) async {
      // Create bloc with known initial state
      final bloc = TestBloc(initialState: TestState(value: 42));
      resolver = TestResolver(blocs: {TestBloc: bloc});

      // Build widget with explicit resolver
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: TestWidget(resolver: resolver),
        ),
      ));

      // Verify initial state is displayed
      expect(find.text('Value: 42'), findsOneWidget);
    });

    testWidgets('StatelessJuiceWidget updates when state changes',
        (tester) async {
      // Create bloc with initial state
      final bloc = TestBloc(initialState: TestState(value: 0));
      resolver = TestResolver(blocs: {TestBloc: bloc});

      // Build widget with explicit resolver
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: TestWidget(resolver: resolver),
        ),
      ));

      // Verify initial state
      expect(find.text('Value: 0'), findsOneWidget);

      // Update state
      await bloc.send(TestEvent());
      await tester.pump();

      // Verify updated state is displayed
      expect(find.text('Value: 1'), findsOneWidget);
    });

    testWidgets('Widget rebuilds only for specified groups', (tester) async {
      // Create bloc with initial state
      final bloc = TestBloc(initialState: TestState(value: 0));
      resolver = TestResolver(blocs: {TestBloc: bloc});

      // Track build count
      int buildCount = 0;

      // Build widget with specific group and explicit resolver
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: TestWidget(
            resolver: resolver,
            groups: const {"specific-group"},
            doOnBuild: () => buildCount++,
          ),
        ),
      ));

      // Initial build
      expect(buildCount, 1);

      // Send event with non-matching group
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
      // Create bloc with initial state
      final bloc = TestBloc(initialState: TestState(value: 0));
      resolver = TestResolver(blocs: {TestBloc: bloc});

      // Track build count
      int buildCount = 0;

      var widget = MaterialApp(
        home: Scaffold(
          body: TestWidget(
            resolver: resolver,
            groups: const {"my-group"},
            doOnBuild: () => buildCount++,
          ),
        ),
      );

      // Build widget with wildcard group
      await tester.pumpWidget(widget);
      expect(buildCount, 1);

      // Send event with specific group
      await bloc.send(TestEvent(groups: {"*"}));
      await tester.pump();

      expect(buildCount, 2);

      await bloc.send(TestEvent(groups: {"another-group"}));
      await tester.pump();

      expect(buildCount, 2);
    });
  });
}
