import 'package:flutter_test/flutter_test.dart';
import 'package:juice/juice.dart';

/// Helper extension to filter streams by type (portable replacement for whereType)
extension StreamTypeFilter<T> on Stream<T> {
  Stream<S> ofType<S extends T>() => where((e) => e is S).cast<S>();
}

void main() {
  setUp(() {
    BlocScope.reset();
  });

  tearDown(() {
    BlocScope.reset();
  });

  group('LifecycleBloc', () {
    test('generateScopeId returns unique sequential IDs', () {
      final bloc = LifecycleBloc();

      final id1 = bloc.generateScopeId();
      final id2 = bloc.generateScopeId();
      final id3 = bloc.generateScopeId();

      expect(id1, 'scope_0');
      expect(id2, 'scope_1');
      expect(id3, 'scope_2');

      bloc.close();
    });

    test('initial state has no scopes', () {
      final bloc = LifecycleBloc();

      expect(bloc.state.scopes, isEmpty);

      bloc.close();
    });

    test('config has default values', () {
      final bloc = LifecycleBloc();

      expect(bloc.config.cleanupTimeout, const Duration(seconds: 2));
      expect(bloc.config.onCleanupTimeout, isNull);

      bloc.close();
    });

    test('config can be customized', () {
      final bloc = LifecycleBloc(
        config: LifecycleBlocConfig(
          cleanupTimeout: const Duration(seconds: 5),
          onCleanupTimeout: (id, name) {},
        ),
      );

      expect(bloc.config.cleanupTimeout, const Duration(seconds: 5));
      expect(bloc.config.onCleanupTimeout, isNotNull);

      bloc.close();
    });

    group('StartScopeEvent', () {
      test('adds scope to state', () async {
        final bloc = LifecycleBloc();
        final scope = FeatureScope('test');

        final event = StartScopeEvent(name: 'test', scope: scope);
        bloc.send(event);
        final scopeId = await event.result;

        expect(scopeId, 'scope_0');
        expect(bloc.state.scopes.containsKey(scopeId), isTrue);
        expect(bloc.state.scopes[scopeId]!.name, 'test');
        expect(bloc.state.scopes[scopeId]!.phase, ScopePhase.active);

        await bloc.close();
      });

      test('publishes ScopeStartedNotification', () async {
        final bloc = LifecycleBloc();
        final scope = FeatureScope('test');

        final notifications = <ScopeNotification>[];
        bloc.notifications.listen(notifications.add);

        final event = StartScopeEvent(name: 'test', scope: scope);
        bloc.send(event);
        await event.result;

        await Future.delayed(Duration(milliseconds: 10));

        expect(notifications.length, 1);
        expect(notifications.first, isA<ScopeStartedNotification>());
        final notification = notifications.first as ScopeStartedNotification;
        expect(notification.scopeName, 'test');
        expect(notification.scopeId, 'scope_0');

        await bloc.close();
      });
    });

    group('EndScopeEvent', () {
      test('returns notFound for unknown scope', () async {
        final bloc = LifecycleBloc();

        final event = EndScopeEvent(scopeId: 'unknown');
        bloc.send(event);
        final result = await event.result;

        expect(result.found, isFalse);
        expect(result, EndScopeResult.notFound);

        await bloc.close();
      });

      test('ends scope by scopeId', () async {
        final bloc = LifecycleBloc();
        final scope = FeatureScope('test');

        // Start scope
        final startEvent = StartScopeEvent(name: 'test', scope: scope);
        bloc.send(startEvent);
        final scopeId = await startEvent.result;

        // End scope
        final endEvent = EndScopeEvent(scopeId: scopeId);
        bloc.send(endEvent);
        final result = await endEvent.result;

        expect(result.found, isTrue);
        expect(result.cleanupCompleted, isTrue);
        expect(bloc.state.scopes.containsKey(scopeId), isFalse);

        await bloc.close();
      });

      test('ends scope by scopeName', () async {
        final bloc = LifecycleBloc();
        final scope = FeatureScope('test');

        // Start scope
        final startEvent = StartScopeEvent(name: 'test', scope: scope);
        bloc.send(startEvent);
        await startEvent.result;

        // End scope by name
        final endEvent = EndScopeEvent(scopeName: 'test');
        bloc.send(endEvent);
        final result = await endEvent.result;

        expect(result.found, isTrue);
        expect(bloc.state.scopes, isEmpty);

        await bloc.close();
      });

      test('publishes ScopeEndingNotification with barrier', () async {
        final bloc = LifecycleBloc();
        final scope = FeatureScope('test');

        // Start scope
        final startEvent = StartScopeEvent(name: 'test', scope: scope);
        bloc.send(startEvent);
        final scopeId = await startEvent.result;

        final notifications = <ScopeNotification>[];
        bloc.notifications
            .ofType<ScopeEndingNotification>()
            .listen(notifications.add);

        // End scope
        final endEvent = EndScopeEvent(scopeId: scopeId);
        bloc.send(endEvent);
        await endEvent.result;

        expect(notifications.length, 1);
        final notification = notifications.first as ScopeEndingNotification;
        expect(notification.scopeId, scopeId);
        expect(notification.barrier, isNotNull);

        await bloc.close();
      });

      test('publishes ScopeEndedNotification after cleanup', () async {
        final bloc = LifecycleBloc();
        final scope = FeatureScope('test');

        // Start scope
        final startEvent = StartScopeEvent(name: 'test', scope: scope);
        bloc.send(startEvent);
        final scopeId = await startEvent.result;

        final endedNotifications = <ScopeEndedNotification>[];
        bloc.notifications
            .ofType<ScopeEndedNotification>()
            .listen(endedNotifications.add);

        // End scope
        final endEvent = EndScopeEvent(scopeId: scopeId);
        bloc.send(endEvent);
        await endEvent.result;

        await Future.delayed(Duration(milliseconds: 10));

        expect(endedNotifications.length, 1);
        expect(endedNotifications.first.scopeId, scopeId);
        expect(endedNotifications.first.cleanupCompleted, isTrue);

        await bloc.close();
      });

      test('awaits cleanup barrier tasks', () async {
        final bloc = LifecycleBloc();
        final scope = FeatureScope('test');

        // Start scope
        final startEvent = StartScopeEvent(name: 'test', scope: scope);
        bloc.send(startEvent);
        final scopeId = await startEvent.result;

        var cleanupDone = false;

        // Subscribe to ending notification and register cleanup
        bloc.notifications.ofType<ScopeEndingNotification>().listen((n) {
          n.barrier.add(Future.delayed(Duration(milliseconds: 50), () {
            cleanupDone = true;
          }));
        });

        // End scope
        final endEvent = EndScopeEvent(scopeId: scopeId);
        bloc.send(endEvent);
        final result = await endEvent.result;

        expect(cleanupDone, isTrue);
        expect(result.cleanupTaskCount, 1);
        expect(result.cleanupCompleted, isTrue);

        await bloc.close();
      });

      test('handles cleanup timeout', () async {
        var timeoutId = '';
        var timeoutName = '';
        final bloc = LifecycleBloc(
          config: LifecycleBlocConfig(
            cleanupTimeout: const Duration(milliseconds: 50),
            onCleanupTimeout: (id, name) {
              timeoutId = id;
              timeoutName = name;
            },
          ),
        );
        final scope = FeatureScope('test');

        // Start scope
        final startEvent = StartScopeEvent(name: 'test', scope: scope);
        bloc.send(startEvent);
        final scopeId = await startEvent.result;

        // Subscribe and register slow cleanup
        bloc.notifications.ofType<ScopeEndingNotification>().listen((n) {
          n.barrier.add(Future.delayed(Duration(seconds: 5)));
        });

        // End scope
        final endEvent = EndScopeEvent(scopeId: scopeId);
        bloc.send(endEvent);
        final result = await endEvent.result;

        expect(result.cleanupCompleted, isFalse);
        expect(timeoutId, scopeId);
        expect(timeoutName, 'test');

        await bloc.close();
      });
    });

    group('idempotency', () {
      test('concurrent end calls return same future', () async {
        final bloc = LifecycleBloc();
        final scope = FeatureScope('test');

        // Start scope
        final startEvent = StartScopeEvent(name: 'test', scope: scope);
        bloc.send(startEvent);
        final scopeId = await startEvent.result;

        // Register slow cleanup
        bloc.notifications.ofType<ScopeEndingNotification>().listen((n) {
          n.barrier.add(Future.delayed(Duration(milliseconds: 100)));
        });

        // Send multiple end events concurrently
        final endEvent1 = EndScopeEvent(scopeId: scopeId);
        final endEvent2 = EndScopeEvent(scopeId: scopeId);
        bloc.send(endEvent1);
        bloc.send(endEvent2);

        final result1 = await endEvent1.result;
        final result2 = await endEvent2.result;

        // Both should have the same outcome
        expect(result1.found, isTrue);
        expect(result2.found, isTrue);
        expect(result1.cleanupCompleted, result2.cleanupCompleted);

        await bloc.close();
      });
    });

    group('notifications', () {
      test('stream is broadcast', () async {
        final bloc = LifecycleBloc();

        final listener1 = <ScopeNotification>[];
        final listener2 = <ScopeNotification>[];

        bloc.notifications.listen(listener1.add);
        bloc.notifications.listen(listener2.add);

        final scope = FeatureScope('test');
        final event = StartScopeEvent(name: 'test', scope: scope);
        bloc.send(event);
        await event.result;

        await Future.delayed(Duration(milliseconds: 10));

        expect(listener1.length, 1);
        expect(listener2.length, 1);

        await bloc.close();
      });

      test('can filter by type', () async {
        final bloc = LifecycleBloc();
        final scope = FeatureScope('test');

        final started = <ScopeStartedNotification>[];
        final ending = <ScopeEndingNotification>[];
        final ended = <ScopeEndedNotification>[];

        bloc.notifications
            .ofType<ScopeStartedNotification>()
            .listen(started.add);
        bloc.notifications.ofType<ScopeEndingNotification>().listen(ending.add);
        bloc.notifications.ofType<ScopeEndedNotification>().listen(ended.add);

        // Start and end scope
        final startEvent = StartScopeEvent(name: 'test', scope: scope);
        bloc.send(startEvent);
        final scopeId = await startEvent.result;

        final endEvent = EndScopeEvent(scopeId: scopeId);
        bloc.send(endEvent);
        await endEvent.result;

        await Future.delayed(Duration(milliseconds: 10));

        expect(started.length, 1);
        expect(ending.length, 1);
        expect(ended.length, 1);

        await bloc.close();
      });
    });
  });

  group('ScopeState', () {
    test('byName returns scopes with matching name', () {
      final scope1 = FeatureScope('checkout');
      final scope2 = FeatureScope('checkout');
      final scope3 = FeatureScope('other');

      final state = ScopeState(scopes: {
        'scope_0': ScopeInfo(
          id: 'scope_0',
          name: 'checkout',
          phase: ScopePhase.active,
          startedAt: DateTime.now(),
          scope: scope1,
        ),
        'scope_1': ScopeInfo(
          id: 'scope_1',
          name: 'checkout',
          phase: ScopePhase.active,
          startedAt: DateTime.now(),
          scope: scope2,
        ),
        'scope_2': ScopeInfo(
          id: 'scope_2',
          name: 'other',
          phase: ScopePhase.active,
          startedAt: DateTime.now(),
          scope: scope3,
        ),
      });

      final checkoutScopes = state.byName('checkout');

      expect(checkoutScopes.length, 2);
      expect(checkoutScopes.every((s) => s.name == 'checkout'), isTrue);
    });

    test('isActive checks for active scopes by name', () {
      final scope = FeatureScope('test');

      final activeState = ScopeState(scopes: {
        'scope_0': ScopeInfo(
          id: 'scope_0',
          name: 'test',
          phase: ScopePhase.active,
          startedAt: DateTime.now(),
          scope: scope,
        ),
      });

      final endingState = ScopeState(scopes: {
        'scope_0': ScopeInfo(
          id: 'scope_0',
          name: 'test',
          phase: ScopePhase.ending,
          startedAt: DateTime.now(),
          scope: scope,
        ),
      });

      expect(activeState.isActive('test'), isTrue);
      expect(endingState.isActive('test'), isFalse);
    });

    test('inPhase filters by phase', () {
      final scope1 = FeatureScope('active');
      final scope2 = FeatureScope('ending');

      final state = ScopeState(scopes: {
        'scope_0': ScopeInfo(
          id: 'scope_0',
          name: 'active',
          phase: ScopePhase.active,
          startedAt: DateTime.now(),
          scope: scope1,
        ),
        'scope_1': ScopeInfo(
          id: 'scope_1',
          name: 'ending',
          phase: ScopePhase.ending,
          startedAt: DateTime.now(),
          scope: scope2,
        ),
      });

      expect(state.inPhase(ScopePhase.active).length, 1);
      expect(state.inPhase(ScopePhase.ending).length, 1);
    });
  });
}
