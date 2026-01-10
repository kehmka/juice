import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice/juice.dart';
import '../test_helpers.dart';

void main() {
  group('BlocScope Lifecycle Tests', () {
    setUp(() async {
      await BlocScope.reset();
    });

    tearDown(() async {
      await BlocScope.reset();
    });

    group('Permanent Lifecycle', () {
      test('Permanent bloc persists until endAll', () async {
        BlocScope.register<TestBloc>(
          () => TestBloc(initialState: TestState(value: 0)),
          lifecycle: BlocLifecycle.permanent,
        );

        final bloc = BlocScope.get<TestBloc>();
        expect(bloc.isClosed, false);

        // Get same instance again
        final bloc2 = BlocScope.get<TestBloc>();
        expect(identical(bloc, bloc2), true);

        // Still active
        expect(bloc.isClosed, false);

        await BlocScope.endAll();
        expect(bloc.isClosed, true);
      });

      test('Permanent bloc can be ended individually', () async {
        BlocScope.register<TestBloc>(
          () => TestBloc(initialState: TestState(value: 0)),
          lifecycle: BlocLifecycle.permanent,
        );

        final bloc = BlocScope.get<TestBloc>();
        expect(bloc.isClosed, false);

        await BlocScope.end<TestBloc>();
        expect(bloc.isClosed, true);
      });
    });

    group('Leased Lifecycle', () {
      test('Leased bloc is created on first lease', () async {
        BlocScope.register<TestBloc>(
          () => TestBloc(initialState: TestState(value: 0)),
          lifecycle: BlocLifecycle.leased,
        );

        final diagnostics = BlocScope.diagnostics<TestBloc>();
        expect(diagnostics?.isActive, false);

        final lease = BlocScope.lease<TestBloc>();
        expect(lease.bloc.isClosed, false);

        final diagnosticsAfter = BlocScope.diagnostics<TestBloc>();
        expect(diagnosticsAfter?.isActive, true);

        lease.dispose();
        await Future.delayed(const Duration(milliseconds: 50));
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

        expect(lease.bloc.isClosed, true);
      });

      test('Multiple leases keep bloc alive', () async {
        BlocScope.register<TestBloc>(
          () => TestBloc(initialState: TestState(value: 0)),
          lifecycle: BlocLifecycle.leased,
        );

        final lease1 = BlocScope.lease<TestBloc>();
        final lease2 = BlocScope.lease<TestBloc>();
        final lease3 = BlocScope.lease<TestBloc>();

        // All leases reference same bloc
        expect(identical(lease1.bloc, lease2.bloc), true);
        expect(identical(lease2.bloc, lease3.bloc), true);

        // Release first two leases
        lease1.dispose();
        await Future.delayed(const Duration(milliseconds: 50));
        expect(lease2.bloc.isClosed, false);

        lease2.dispose();
        await Future.delayed(const Duration(milliseconds: 50));
        expect(lease3.bloc.isClosed, false);

        // Release last lease - bloc should close
        lease3.dispose();
        await Future.delayed(const Duration(milliseconds: 50));
        expect(lease3.bloc.isClosed, true);
      });

      test('Lease dispose is idempotent', () async {
        BlocScope.register<TestBloc>(
          () => TestBloc(initialState: TestState(value: 0)),
          lifecycle: BlocLifecycle.leased,
        );

        final lease = BlocScope.lease<TestBloc>();

        // Multiple dispose calls should not throw or double-decrement
        lease.dispose();
        lease.dispose();
        lease.dispose();

        await Future.delayed(const Duration(milliseconds: 50));
        expect(lease.bloc.isClosed, true);
      });

      test('Lease count is tracked correctly', () async {
        BlocScope.register<TestBloc>(
          () => TestBloc(initialState: TestState(value: 0)),
          lifecycle: BlocLifecycle.leased,
        );

        var diagnostics = BlocScope.diagnostics<TestBloc>();
        expect(diagnostics?.leaseCount, 0);

        final lease1 = BlocScope.lease<TestBloc>();
        diagnostics = BlocScope.diagnostics<TestBloc>();
        expect(diagnostics?.leaseCount, 1);

        final lease2 = BlocScope.lease<TestBloc>();
        diagnostics = BlocScope.diagnostics<TestBloc>();
        expect(diagnostics?.leaseCount, 2);

        lease1.dispose();
        await Future.delayed(const Duration(milliseconds: 20));
        diagnostics = BlocScope.diagnostics<TestBloc>();
        expect(diagnostics?.leaseCount, 1);

        lease2.dispose();
        await Future.delayed(const Duration(milliseconds: 50));
      });

      test('New bloc instance created after previous is closed', () async {
        BlocScope.register<TestBloc>(
          () => TestBloc(initialState: TestState(value: 0)),
          lifecycle: BlocLifecycle.leased,
        );

        final lease1 = BlocScope.lease<TestBloc>();
        final bloc1 = lease1.bloc;

        // Modify state
        await bloc1.send(TestEvent());
        expect(bloc1.state.value, 1);

        lease1.dispose();
        await Future.delayed(const Duration(milliseconds: 50));
        expect(bloc1.isClosed, true);

        // Get new lease - should be fresh instance
        final lease2 = BlocScope.lease<TestBloc>();
        final bloc2 = lease2.bloc;

        expect(identical(bloc1, bloc2), false);
        expect(bloc2.state.value, 0); // Fresh state

        lease2.dispose();
        await Future.delayed(const Duration(milliseconds: 50));
      });
    });

    group('Feature Lifecycle', () {
      test('Feature bloc is disposed when feature ends', () async {
        final scope = FeatureScope('checkout');

        BlocScope.register<TestBloc>(
          () => TestBloc(initialState: TestState(value: 0)),
          lifecycle: BlocLifecycle.feature,
          scope: scope,
        );

        final bloc = BlocScope.get<TestBloc>(scope: scope);
        expect(bloc.isClosed, false);

        // Call BlocScope.endFeature (scope.end() just marks scope as ended)
        await BlocScope.endFeature(scope);
        expect(bloc.isClosed, true);
      });

      test('Multiple blocs in same feature scope are disposed together',
          () async {
        final scope = FeatureScope('checkout');

        BlocScope.register<TestBloc>(
          () => TestBloc(initialState: TestState(value: 0)),
          lifecycle: BlocLifecycle.feature,
          scope: scope,
        );
        BlocScope.register<SecondTestBloc>(
          () => SecondTestBloc(initialState: SecondTestState(status: 'init')),
          lifecycle: BlocLifecycle.feature,
          scope: scope,
        );

        final bloc1 = BlocScope.get<TestBloc>(scope: scope);
        final bloc2 = BlocScope.get<SecondTestBloc>(scope: scope);

        expect(bloc1.isClosed, false);
        expect(bloc2.isClosed, false);

        await BlocScope.endFeature(scope);

        expect(bloc1.isClosed, true);
        expect(bloc2.isClosed, true);
      });

      test('Scoped blocs are independent of global blocs', () async {
        final scope = FeatureScope('feature1');

        // Register global bloc
        BlocScope.register<TestBloc>(
          () => TestBloc(initialState: TestState(value: 0)),
          lifecycle: BlocLifecycle.permanent,
        );

        // Register scoped bloc
        BlocScope.register<SecondTestBloc>(
          () => SecondTestBloc(initialState: SecondTestState(status: 'scoped')),
          lifecycle: BlocLifecycle.feature,
          scope: scope,
        );

        final globalBloc = BlocScope.get<TestBloc>();
        final scopedBloc = BlocScope.get<SecondTestBloc>(scope: scope);

        // End feature scope using BlocScope.endFeature
        await BlocScope.endFeature(scope);

        // Scoped bloc should be closed
        expect(scopedBloc.isClosed, true);

        // Global bloc should still be active
        expect(globalBloc.isClosed, false);
      });
    });

    group('Registration Validation', () {
      test('Duplicate registration with same lifecycle is idempotent', () {
        BlocScope.register<TestBloc>(
          () => TestBloc(initialState: TestState(value: 0)),
          lifecycle: BlocLifecycle.permanent,
        );

        // Should not throw
        BlocScope.register<TestBloc>(
          () => TestBloc(initialState: TestState(value: 0)),
          lifecycle: BlocLifecycle.permanent,
        );
      });

      test('Duplicate registration with different lifecycle throws', () {
        BlocScope.register<TestBloc>(
          () => TestBloc(initialState: TestState(value: 0)),
          lifecycle: BlocLifecycle.permanent,
        );

        expect(
          () => BlocScope.register<TestBloc>(
            () => TestBloc(initialState: TestState(value: 0)),
            lifecycle: BlocLifecycle.leased,
          ),
          throwsStateError,
        );
      });

      test('Accessing unregistered bloc throws', () {
        expect(
          () => BlocScope.get<TestBloc>(),
          throwsStateError,
        );
      });

      test('Leasing unregistered bloc throws', () {
        expect(
          () => BlocScope.lease<TestBloc>(),
          throwsStateError,
        );
      });
    });

    group('Async Lease Acquisition', () {
      test('leaseAsync waits for bloc to finish closing', () async {
        BlocScope.register<TestBloc>(
          () => TestBloc(initialState: TestState(value: 0)),
          lifecycle: BlocLifecycle.leased,
        );

        final lease1 = BlocScope.lease<TestBloc>();
        final bloc1 = lease1.bloc;
        lease1.dispose();

        // Start async lease acquisition while closing
        final leaseFuture = BlocScope.leaseAsync<TestBloc>();

        final lease2 = await leaseFuture;
        expect(lease2.bloc.isClosed, false);

        // Should be new instance
        expect(identical(bloc1, lease2.bloc), false);

        lease2.dispose();
        await Future.delayed(const Duration(milliseconds: 50));
      });
    });

    group('Diagnostics', () {
      test('Diagnostics returns correct information', () async {
        BlocScope.register<TestBloc>(
          () => TestBloc(initialState: TestState(value: 0)),
          lifecycle: BlocLifecycle.leased,
        );

        // Before creation
        var diagnostics = BlocScope.diagnostics<TestBloc>();
        expect(diagnostics?.type, TestBloc);
        expect(diagnostics?.lifecycle, BlocLifecycle.leased);
        expect(diagnostics?.isActive, false);
        expect(diagnostics?.leaseCount, 0);
        expect(diagnostics?.isClosing, false);

        // After lease
        final lease = BlocScope.lease<TestBloc>();
        diagnostics = BlocScope.diagnostics<TestBloc>();
        expect(diagnostics?.isActive, true);
        expect(diagnostics?.leaseCount, 1);
        expect(diagnostics?.createdAt, isNotNull);

        lease.dispose();
        await Future.delayed(const Duration(milliseconds: 50));
      });

      test('Diagnostics returns null for unregistered bloc', () {
        final diagnostics = BlocScope.diagnostics<TestBloc>();
        expect(diagnostics, isNull);
      });

      test('isRegistered returns correct values', () {
        expect(BlocScope.isRegistered<TestBloc>(), false);

        BlocScope.register<TestBloc>(
          () => TestBloc(initialState: TestState(value: 0)),
          lifecycle: BlocLifecycle.permanent,
        );

        expect(BlocScope.isRegistered<TestBloc>(), true);
      });
    });

    group('Edge Cases', () {
      test('Closing bloc during active use is safe', () async {
        BlocScope.register<TestBloc>(
          () => TestBloc(initialState: TestState(value: 0)),
          lifecycle: BlocLifecycle.leased,
        );

        final lease = BlocScope.lease<TestBloc>();
        final bloc = lease.bloc;

        // Start an operation
        final sendFuture = bloc.send(TestEvent());

        // Dispose lease immediately
        lease.dispose();

        // Wait for everything to settle
        await sendFuture;
        await Future.delayed(const Duration(milliseconds: 100));

        // Should not throw
      });

      test('endAll handles mixed lifecycles', () async {
        // Register different lifecycles
        BlocScope.register<TestBloc>(
          () => TestBloc(initialState: TestState(value: 0)),
          lifecycle: BlocLifecycle.permanent,
        );

        BlocScope.register<SecondTestBloc>(
          () => SecondTestBloc(initialState: SecondTestState(status: 'init')),
          lifecycle: BlocLifecycle.leased,
        );

        final permanentBloc = BlocScope.get<TestBloc>();
        final lease = BlocScope.lease<SecondTestBloc>();
        final leasedBloc = lease.bloc;

        await BlocScope.endAll();

        expect(permanentBloc.isClosed, true);
        expect(leasedBloc.isClosed, true);
      });

      test('Stream subscriptions are cleaned up on close', () async {
        BlocScope.register<TestBloc>(
          () => TestBloc(initialState: TestState(value: 0)),
          lifecycle: BlocLifecycle.leased,
        );

        final lease = BlocScope.lease<TestBloc>();
        final bloc = lease.bloc;

        final completer = Completer<void>();
        final subscription = bloc.stream.listen(
          (_) {},
          onDone: () => completer.complete(),
        );

        lease.dispose();

        // Stream should complete
        await expectLater(
          completer.future.timeout(const Duration(seconds: 1)),
          completes,
        );

        await subscription.cancel();
      });
    });
  });
}
