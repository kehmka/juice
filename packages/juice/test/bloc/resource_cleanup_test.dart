import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice/juice.dart';
import '../test_helpers.dart';

void main() {
  group('Resource Cleanup Tests', () {
    late TestBloc bloc;

    setUp(() {
      bloc = TestBloc(initialState: TestState(value: 0));
    });

    tearDown(() async {
      if (!bloc.isClosed) {
        await bloc.close();
      }
    });

    test('Bloc closes and sets isClosed flag', () async {
      expect(bloc.isClosed, false);

      await bloc.close();

      expect(bloc.isClosed, true);
    });

    test('Bloc close is idempotent - multiple calls are safe', () async {
      await bloc.close();
      expect(bloc.isClosed, true);

      // Second close should not throw
      await bloc.close();
      expect(bloc.isClosed, true);
    });

    test('Stream subscriptions receive done event on close', () async {
      final completer = Completer<void>();
      final subscription = bloc.stream.listen(
        (_) {},
        onDone: () => completer.complete(),
      );

      await bloc.close();

      // Should complete within reasonable time
      await expectLater(
        completer.future.timeout(const Duration(seconds: 1)),
        completes,
      );

      await subscription.cancel();
    });

    test('Stream stops emitting after close', () async {
      final statuses = <StreamStatus>[];
      final subscription = bloc.stream.listen(statuses.add);

      // Send event before close
      await bloc.send(TestEvent());
      expect(statuses.length, 1);

      await bloc.close();

      // Sending event to closed bloc should not emit (logs warning)
      bloc.send(TestEvent());
      await Future.delayed(const Duration(milliseconds: 50));

      // Should still only have 1 status from before close
      expect(statuses.length, 1);

      await subscription.cancel();
    });

    test('State is preserved after close', () async {
      await bloc.send(TestEvent());
      expect(bloc.state.value, 1);

      await bloc.close();

      // State should still be accessible
      expect(bloc.state.value, 1);
    });

    test('Current status is preserved after close', () async {
      await bloc.send(TestEvent());
      final statusBeforeClose = bloc.currentStatus;

      await bloc.close();

      // Current status should still be accessible
      expect(bloc.currentStatus, statusBeforeClose);
    });
  });

  group('Nested Bloc Cleanup Tests', () {
    setUp(() async {
      await BlocScope.reset();
    });

    tearDown(() async {
      await BlocScope.reset();
    });

    test('Parent bloc closing does not affect child bloc', () async {
      // Register both blocs
      BlocScope.register<TestBloc>(
        () => TestBloc(initialState: TestState(value: 0)),
        lifecycle: BlocLifecycle.permanent,
      );
      BlocScope.register<SecondTestBloc>(
        () => SecondTestBloc(initialState: SecondTestState(status: 'init')),
        lifecycle: BlocLifecycle.permanent,
      );

      final parent = BlocScope.get<TestBloc>();
      final child = BlocScope.get<SecondTestBloc>();

      // Close parent
      await BlocScope.end<TestBloc>();

      // Child should still be active
      expect(child.isClosed, false);

      // Child should still work
      child.updateStatus('updated');
      expect(child.state.status, 'updated');
    });

    test('BlocScope.endAll closes all registered blocs', () async {
      BlocScope.register<TestBloc>(
        () => TestBloc(initialState: TestState(value: 0)),
        lifecycle: BlocLifecycle.permanent,
      );
      BlocScope.register<SecondTestBloc>(
        () => SecondTestBloc(initialState: SecondTestState(status: 'init')),
        lifecycle: BlocLifecycle.permanent,
      );

      // Get instances to create them
      final bloc1 = BlocScope.get<TestBloc>();
      final bloc2 = BlocScope.get<SecondTestBloc>();

      expect(bloc1.isClosed, false);
      expect(bloc2.isClosed, false);

      await BlocScope.endAll();

      expect(bloc1.isClosed, true);
      expect(bloc2.isClosed, true);
    });
  });

  group('Leased Bloc Cleanup Tests', () {
    setUp(() async {
      await BlocScope.reset();
    });

    tearDown(() async {
      await BlocScope.reset();
    });

    test('Leased bloc is disposed when last lease is released', () async {
      BlocScope.register<TestBloc>(
        () => TestBloc(initialState: TestState(value: 0)),
        lifecycle: BlocLifecycle.leased,
      );

      final lease = BlocScope.lease<TestBloc>();
      expect(lease.bloc.isClosed, false);

      lease.dispose();

      // Wait for async close to complete
      await Future.delayed(const Duration(milliseconds: 50));

      // After lease release, bloc should be closed
      expect(lease.bloc.isClosed, true);
    });

    test('Multiple leases keep bloc alive', () async {
      BlocScope.register<TestBloc>(
        () => TestBloc(initialState: TestState(value: 0)),
        lifecycle: BlocLifecycle.leased,
      );

      final lease1 = BlocScope.lease<TestBloc>();
      final lease2 = BlocScope.lease<TestBloc>();

      // Both should reference same bloc
      expect(identical(lease1.bloc, lease2.bloc), true);

      // Release first lease
      lease1.dispose();
      await Future.delayed(const Duration(milliseconds: 50));

      // Bloc should still be alive (lease2 holds it)
      expect(lease2.bloc.isClosed, false);

      // Release second lease
      lease2.dispose();
      await Future.delayed(const Duration(milliseconds: 50));

      // Now bloc should be closed
      expect(lease2.bloc.isClosed, true);
    });

    test('Lease dispose is idempotent', () async {
      BlocScope.register<TestBloc>(
        () => TestBloc(initialState: TestState(value: 0)),
        lifecycle: BlocLifecycle.leased,
      );

      final lease = BlocScope.lease<TestBloc>();

      // Multiple dispose calls should not throw
      lease.dispose();
      lease.dispose();
      lease.dispose();

      await Future.delayed(const Duration(milliseconds: 50));
      expect(lease.bloc.isClosed, true);
    });
  });
}
