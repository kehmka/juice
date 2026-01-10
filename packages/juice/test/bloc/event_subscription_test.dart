import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice/juice.dart';

// Test States
class SourceState extends BlocState {
  final int value;
  SourceState({required this.value});
  SourceState copyWith({int? value}) => SourceState(value: value ?? this.value);
}

class DestState extends BlocState {
  final String message;
  DestState({required this.message});
  DestState copyWith({String? message}) =>
      DestState(message: message ?? this.message);
}

// Test Events
class SourceEvent extends EventBase {
  final int delta;
  SourceEvent({this.delta = 1});
}

class DestEvent extends EventBase {
  final String message;
  DestEvent({required this.message});
}

// Test Use Cases
class SourceUseCase extends BlocUseCase<SourceBloc, SourceEvent> {
  @override
  Future<void> execute(SourceEvent event) async {
    emitUpdate(
      newState: bloc.state.copyWith(value: bloc.state.value + event.delta),
      groupsToRebuild: {'source'},
    );
  }
}

class DestUseCase extends BlocUseCase<DestBloc, DestEvent> {
  @override
  Future<void> execute(DestEvent event) async {
    emitUpdate(
      newState: bloc.state.copyWith(message: event.message),
      groupsToRebuild: {'dest'},
    );
  }
}

// Test Blocs
class SourceBloc extends JuiceBloc<SourceState> {
  SourceBloc()
      : super(
          SourceState(value: 0),
          [
            () => UseCaseBuilder(
                  typeOfEvent: SourceEvent,
                  useCaseGenerator: () => SourceUseCase(),
                ),
          ],
          [],
        );
}

class DestBloc extends JuiceBloc<DestState> {
  DestBloc({List<UseCaseBuilderGenerator>? builders})
      : super(
          DestState(message: 'initial'),
          builders ??
              [
                () => UseCaseBuilder(
                      typeOfEvent: DestEvent,
                      useCaseGenerator: () => DestUseCase(),
                    ),
              ],
          [],
        );
}

// Test resolver for EventSubscription
class TestEventResolver implements BlocDependencyResolver {
  final Map<Type, JuiceBloc> blocs;

  TestEventResolver(this.blocs);

  @override
  T resolve<T extends JuiceBloc<BlocState>>({Map<String, dynamic>? args}) {
    final bloc = blocs[T];
    if (bloc == null) {
      throw StateError('Bloc $T not registered');
    }
    return bloc as T;
  }

  @override
  BlocLease<T> lease<T extends JuiceBloc<BlocState>>({Object? scope}) {
    return BlocLease<T>(resolve<T>(), () {});
  }

  @override
  Future<void> disposeAll() async {
    for (final bloc in blocs.values) {
      await bloc.close();
    }
  }
}

void main() {
  group('EventSubscription Tests', () {
    late SourceBloc sourceBloc;
    late DestBloc destBloc;
    late TestEventResolver resolver;

    setUp(() {
      sourceBloc = SourceBloc();
      destBloc = DestBloc(builders: [
        () => UseCaseBuilder(
              typeOfEvent: DestEvent,
              useCaseGenerator: () => DestUseCase(),
            ),
        () => EventSubscription<SourceBloc, SourceEvent, DestEvent>(
              toEvent: (e) => DestEvent(message: 'received: ${e.delta}'),
              useCaseGenerator: () => DestUseCase(),
            ),
      ]);
      resolver = TestEventResolver({
        SourceBloc: sourceBloc,
        DestBloc: destBloc,
      });
    });

    tearDown(() async {
      await resolver.disposeAll();
    });

    test('EventSubscription transforms and forwards events', () async {
      // Create subscription with explicit resolver
      final subscription =
          EventSubscription<SourceBloc, SourceEvent, DestEvent>(
        toEvent: (e) => DestEvent(message: 'value: ${e.delta}'),
        useCaseGenerator: () => DestUseCase(),
        resolver: resolver,
      );

      // Set up event handler
      subscription.setEventHandler((event) {
        destBloc.send(event);
      });

      // Initialize subscription
      subscription.initialize();

      // Wait for async initialization
      await Future.delayed(const Duration(milliseconds: 100));

      // Send event to source bloc
      await sourceBloc.send(SourceEvent(delta: 5));

      // Wait for propagation
      await Future.delayed(const Duration(milliseconds: 100));

      // Verify dest bloc received transformed event
      expect(destBloc.state.message, 'value: 5');

      await subscription.close();
    });

    test('EventSubscription closes cleanly', () async {
      final subscription =
          EventSubscription<SourceBloc, SourceEvent, DestEvent>(
        toEvent: (e) => DestEvent(message: 'test'),
        useCaseGenerator: () => DestUseCase(),
        resolver: resolver,
      );

      subscription.setEventHandler((event) {});
      subscription.initialize();
      await Future.delayed(const Duration(milliseconds: 100));

      // Close should not throw
      await subscription.close();

      // Multiple close calls should be safe
      await subscription.close();
    });

    test('EventSubscription respects when predicate', () async {
      int eventCount = 0;

      final subscription =
          EventSubscription<SourceBloc, SourceEvent, DestEvent>(
        toEvent: (e) => DestEvent(message: 'delta: ${e.delta}'),
        useCaseGenerator: () => DestUseCase(),
        when: (e) => e.delta > 3, // Only forward events with delta > 3
        resolver: resolver,
      );

      subscription.setEventHandler((event) {
        eventCount++;
        destBloc.send(event);
      });

      subscription.initialize();
      await Future.delayed(const Duration(milliseconds: 100));

      // Send event with delta <= 3 (should be filtered)
      await sourceBloc.send(SourceEvent(delta: 2));
      await Future.delayed(const Duration(milliseconds: 50));
      expect(eventCount, 0);

      // Send event with delta > 3 (should pass through)
      await sourceBloc.send(SourceEvent(delta: 5));
      await Future.delayed(const Duration(milliseconds: 50));
      expect(eventCount, 1);

      await subscription.close();
    });

    test('EventSubscription handles source bloc close gracefully', () async {
      final subscription =
          EventSubscription<SourceBloc, SourceEvent, DestEvent>(
        toEvent: (e) => DestEvent(message: 'test'),
        useCaseGenerator: () => DestUseCase(),
        resolver: resolver,
      );

      subscription.setEventHandler((event) {});
      subscription.initialize();
      await Future.delayed(const Duration(milliseconds: 100));

      // Close source bloc
      await sourceBloc.close();

      // Wait for subscription to handle the close
      await Future.delayed(const Duration(milliseconds: 100));

      // Should complete without error
      await subscription.close();
    });

    test('EventSubscription does not initialize when already closed', () async {
      final subscription =
          EventSubscription<SourceBloc, SourceEvent, DestEvent>(
        toEvent: (e) => DestEvent(message: 'test'),
        useCaseGenerator: () => DestUseCase(),
        resolver: resolver,
      );

      // Close before initializing
      await subscription.close();

      // Initialize after close - should be no-op
      subscription.initialize();
      await Future.delayed(const Duration(milliseconds: 100));

      // Should not throw or cause issues
    });

    test('EventSubscription handles transformer errors gracefully', () async {
      int eventCount = 0;

      final subscription =
          EventSubscription<SourceBloc, SourceEvent, DestEvent>(
        toEvent: (e) {
          if (e.delta < 0) {
            throw Exception('Negative delta not allowed');
          }
          return DestEvent(message: 'delta: ${e.delta}');
        },
        useCaseGenerator: () => DestUseCase(),
        resolver: resolver,
      );

      subscription.setEventHandler((event) {
        eventCount++;
      });

      subscription.initialize();
      await Future.delayed(const Duration(milliseconds: 100));

      // Send valid event
      await sourceBloc.send(SourceEvent(delta: 1));
      await Future.delayed(const Duration(milliseconds: 50));
      expect(eventCount, 1);

      // Send event that causes transformer to throw
      await sourceBloc.send(SourceEvent(delta: -1));
      await Future.delayed(const Duration(milliseconds: 50));

      // Should still be at 1 (error was caught)
      expect(eventCount, 1);

      // Send another valid event - subscription should still work
      await sourceBloc.send(SourceEvent(delta: 2));
      await Future.delayed(const Duration(milliseconds: 50));
      expect(eventCount, 2);

      await subscription.close();
    });
  });

  group('EventSubscription Race Condition Tests', () {
    test('Close during initialization does not cause errors', () async {
      final sourceBloc = SourceBloc();
      final resolver = TestEventResolver({SourceBloc: sourceBloc});

      final subscription =
          EventSubscription<SourceBloc, SourceEvent, DestEvent>(
        toEvent: (e) => DestEvent(message: 'test'),
        useCaseGenerator: () => DestUseCase(),
        resolver: resolver,
      );

      subscription.setEventHandler((event) {});

      // Initialize and immediately close
      subscription.initialize();
      await subscription.close();

      // Wait to ensure any pending microtasks complete
      await Future.delayed(const Duration(milliseconds: 100));

      // Should not throw
      await sourceBloc.close();
    });

    test('Multiple rapid initialize/close cycles are safe', () async {
      final sourceBloc = SourceBloc();
      final resolver = TestEventResolver({SourceBloc: sourceBloc});

      for (int i = 0; i < 5; i++) {
        final subscription =
            EventSubscription<SourceBloc, SourceEvent, DestEvent>(
          toEvent: (e) => DestEvent(message: 'test'),
          useCaseGenerator: () => DestUseCase(),
          resolver: resolver,
        );

        subscription.setEventHandler((event) {});
        subscription.initialize();
        await Future.delayed(const Duration(milliseconds: 10));
        await subscription.close();
      }

      await sourceBloc.close();
    });
  });
}
