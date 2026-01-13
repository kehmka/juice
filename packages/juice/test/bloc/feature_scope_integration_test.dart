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

  group('FeatureScope integration', () {
    group('without ScopeLifecycleBloc', () {
      test('start() does nothing without ScopeLifecycleBloc', () async {
        final scope = FeatureScope('test');

        await scope.start();

        expect(scope.scopeId, isNull);
      });

      test('end() disposes blocs directly', () async {
        final scope = FeatureScope('test');

        final result = await scope.end();

        expect(result.found, isTrue);
        expect(result.cleanupCompleted, isTrue);
        expect(result.cleanupTaskCount, 0);
      });

      test('create() works without ScopeLifecycleBloc', () async {
        final scope = await FeatureScope.create('test');

        expect(scope.name, 'test');
        expect(scope.scopeId, isNull);
      });
    });

    group('with ScopeLifecycleBloc', () {
      test('start() registers with ScopeLifecycleBloc', () async {
        BlocScope.register<ScopeLifecycleBloc>(
          () => ScopeLifecycleBloc(),
          lifecycle: BlocLifecycle.permanent,
        );
        final scope = FeatureScope('test');

        await scope.start();

        expect(scope.scopeId, 'scope_0');

        final lifecycleBloc = BlocScope.get<ScopeLifecycleBloc>();
        expect(lifecycleBloc.state.scopes.containsKey('scope_0'), isTrue);

        await scope.end();
      });

      test('start() is idempotent', () async {
        BlocScope.register<ScopeLifecycleBloc>(
          () => ScopeLifecycleBloc(),
          lifecycle: BlocLifecycle.permanent,
        );
        final scope = FeatureScope('test');

        await scope.start();
        await scope.start();
        await scope.start();

        expect(scope.scopeId, 'scope_0');

        await scope.end();
      });

      test('end() triggers cleanup sequence', () async {
        BlocScope.register<ScopeLifecycleBloc>(
          () => ScopeLifecycleBloc(),
          lifecycle: BlocLifecycle.permanent,
        );
        final lifecycleBloc = BlocScope.get<ScopeLifecycleBloc>();

        var cleanupDone = false;
        lifecycleBloc.notifications.ofType<ScopeEndingNotification>().listen((n) {
          n.barrier.add(Future.delayed(Duration(milliseconds: 10), () {
            cleanupDone = true;
          }));
        });

        final scope = await FeatureScope.create('test');
        final result = await scope.end();

        expect(result.found, isTrue);
        expect(result.cleanupCompleted, isTrue);
        expect(result.cleanupTaskCount, 1);
        expect(cleanupDone, isTrue);
      });

      test('end() is idempotent', () async {
        BlocScope.register<ScopeLifecycleBloc>(
          () => ScopeLifecycleBloc(),
          lifecycle: BlocLifecycle.permanent,
        );

        final scope = await FeatureScope.create('test');

        final result1 = await scope.end();
        await scope.end(); // Second call
        await scope.end(); // Third call

        expect(result1.found, isTrue);
        // Subsequent calls return the same cached future
        expect(identical(scope.end(), scope.end()), isTrue);
      });

      test('isEnding reflects end state', () async {
        BlocScope.register<ScopeLifecycleBloc>(
          () => ScopeLifecycleBloc(),
          lifecycle: BlocLifecycle.permanent,
        );

        final scope = await FeatureScope.create('test');

        expect(scope.isEnding, isFalse);
        expect(scope.isEnded, isFalse);

        final endFuture = scope.end();
        expect(scope.isEnding, isTrue);

        await endFuture;
        expect(scope.isEnded, isTrue);
      });

      test('create() factory returns started scope', () async {
        BlocScope.register<ScopeLifecycleBloc>(
          () => ScopeLifecycleBloc(),
          lifecycle: BlocLifecycle.permanent,
        );

        final scope = await FeatureScope.create('checkout');

        expect(scope.name, 'checkout');
        expect(scope.scopeId, isNotNull);

        final lifecycleBloc = BlocScope.get<ScopeLifecycleBloc>();
        expect(lifecycleBloc.state.isActive('checkout'), isTrue);

        await scope.end();
      });
    });

    group('subscriber pattern', () {
      test('blocs can subscribe to scope lifecycle', () async {
        BlocScope.register<ScopeLifecycleBloc>(
          () => ScopeLifecycleBloc(),
          lifecycle: BlocLifecycle.permanent,
        );

        final lifecycleBloc = BlocScope.get<ScopeLifecycleBloc>();
        final startedEvents = <ScopeStartedNotification>[];
        final endingEvents = <ScopeEndingNotification>[];
        final endedEvents = <ScopeEndedNotification>[];

        lifecycleBloc.notifications
            .ofType<ScopeStartedNotification>()
            .listen(startedEvents.add);
        lifecycleBloc.notifications
            .ofType<ScopeEndingNotification>()
            .listen(endingEvents.add);
        lifecycleBloc.notifications
            .ofType<ScopeEndedNotification>()
            .listen(endedEvents.add);

        final scope = await FeatureScope.create('test');
        await scope.end();

        await Future.delayed(Duration(milliseconds: 10));

        expect(startedEvents.length, 1);
        expect(startedEvents.first.scopeName, 'test');

        expect(endingEvents.length, 1);
        expect(endingEvents.first.scopeName, 'test');

        expect(endedEvents.length, 1);
        expect(endedEvents.first.scopeName, 'test');
      });

      test('cleanup barrier collects work from multiple subscribers', () async {
        BlocScope.register<ScopeLifecycleBloc>(
          () => ScopeLifecycleBloc(),
          lifecycle: BlocLifecycle.permanent,
        );

        final lifecycleBloc = BlocScope.get<ScopeLifecycleBloc>();
        var cleanup1Done = false;
        var cleanup2Done = false;
        var cleanup3Done = false;

        // Simulate multiple blocs subscribing
        lifecycleBloc.notifications.ofType<ScopeEndingNotification>().listen((n) {
          n.barrier.add(Future.delayed(Duration(milliseconds: 10), () {
            cleanup1Done = true;
          }));
        });

        lifecycleBloc.notifications.ofType<ScopeEndingNotification>().listen((n) {
          n.barrier.add(Future.delayed(Duration(milliseconds: 20), () {
            cleanup2Done = true;
          }));
        });

        lifecycleBloc.notifications.ofType<ScopeEndingNotification>().listen((n) {
          n.barrier.add(Future.delayed(Duration(milliseconds: 15), () {
            cleanup3Done = true;
          }));
        });

        final scope = await FeatureScope.create('test');
        final result = await scope.end();

        expect(cleanup1Done, isTrue);
        expect(cleanup2Done, isTrue);
        expect(cleanup3Done, isTrue);
        expect(result.cleanupTaskCount, 3);
      });
    });

    group('error handling', () {
      test('cleanup task errors are caught and counted', () async {
        BlocScope.register<ScopeLifecycleBloc>(
          () => ScopeLifecycleBloc(),
          lifecycle: BlocLifecycle.permanent,
        );

        final lifecycleBloc = BlocScope.get<ScopeLifecycleBloc>();
        lifecycleBloc.notifications.ofType<ScopeEndingNotification>().listen((n) {
          n.barrier.add(Future.error('cleanup error'));
        });

        final scope = await FeatureScope.create('test');
        final result = await scope.end();

        expect(result.cleanupCompleted, isTrue);
        expect(result.cleanupFailedCount, 1);
        expect(result.success, isFalse);
      });

      test('disposal proceeds even after cleanup timeout', () async {
        BlocScope.register<ScopeLifecycleBloc>(
          () => ScopeLifecycleBloc(
            config: const ScopeLifecycleConfig(
              cleanupTimeout: Duration(milliseconds: 50),
            ),
          ),
          lifecycle: BlocLifecycle.permanent,
        );

        final lifecycleBloc = BlocScope.get<ScopeLifecycleBloc>();
        lifecycleBloc.notifications.ofType<ScopeEndingNotification>().listen((n) {
          n.barrier.add(Future.delayed(Duration(seconds: 5)));
        });

        final scope = await FeatureScope.create('test');
        final result = await scope.end();

        expect(result.cleanupCompleted, isFalse);
        // Scope should still be removed from state
        expect(lifecycleBloc.state.scopes, isEmpty);
        expect(scope.isEnded, isTrue);
      });
    });

    group('ScopeGroups', () {
      test('group names follow expected patterns', () {
        expect(ScopeGroups.active, 'scope:active');
        expect(ScopeGroups.byName('checkout'), 'scope:name:checkout');
        expect(ScopeGroups.byId('scope_0'), 'scope:id:scope_0');
      });
    });
  });
}
