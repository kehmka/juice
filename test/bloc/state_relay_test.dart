import 'package:flutter_test/flutter_test.dart';
import 'package:juice/juice.dart';

// Test States
class SourceState extends BlocState {
  final int counter;
  final bool isActive;
  SourceState({required this.counter, this.isActive = false});
  SourceState copyWith({int? counter, bool? isActive}) => SourceState(
        counter: counter ?? this.counter,
        isActive: isActive ?? this.isActive,
      );
}

class DestState extends BlocState {
  final String message;
  DestState({required this.message});
  DestState copyWith({String? message}) =>
      DestState(message: message ?? this.message);
}

// Test Events
class IncrementEvent extends EventBase {}

class SetActiveEvent extends EventBase {
  final bool active;
  SetActiveEvent({required this.active});
}

class UpdateMessageEvent extends EventBase {
  final String message;
  UpdateMessageEvent({required this.message});
}

// Test Use Cases
class IncrementUseCase extends BlocUseCase<SourceBloc, IncrementEvent> {
  @override
  Future<void> execute(IncrementEvent event) async {
    emitUpdate(
      newState: bloc.state.copyWith(counter: bloc.state.counter + 1),
      groupsToRebuild: {'counter'},
    );
  }
}

class SetActiveUseCase extends BlocUseCase<SourceBloc, SetActiveEvent> {
  @override
  Future<void> execute(SetActiveEvent event) async {
    emitUpdate(
      newState: bloc.state.copyWith(isActive: event.active),
      groupsToRebuild: {'status'},
    );
  }
}

class UpdateMessageUseCase extends BlocUseCase<DestBloc, UpdateMessageEvent> {
  @override
  Future<void> execute(UpdateMessageEvent event) async {
    emitUpdate(
      newState: bloc.state.copyWith(message: event.message),
      groupsToRebuild: {'message'},
    );
  }
}

// Test Blocs
class SourceBloc extends JuiceBloc<SourceState> {
  SourceBloc()
      : super(
          SourceState(counter: 0),
          [
            () => UseCaseBuilder(
                  typeOfEvent: IncrementEvent,
                  useCaseGenerator: () => IncrementUseCase(),
                ),
            () => UseCaseBuilder(
                  typeOfEvent: SetActiveEvent,
                  useCaseGenerator: () => SetActiveUseCase(),
                ),
          ],
          [],
        );
}

class DestBloc extends JuiceBloc<DestState> {
  DestBloc()
      : super(
          DestState(message: 'initial'),
          [
            () => UseCaseBuilder(
                  typeOfEvent: UpdateMessageEvent,
                  useCaseGenerator: () => UpdateMessageUseCase(),
                ),
          ],
          [],
        );
}

// Test resolver
class TestResolver implements BlocDependencyResolver {
  final Map<Type, JuiceBloc> blocs;

  TestResolver(this.blocs);

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
  group('StateRelay Tests', () {
    late SourceBloc sourceBloc;
    late DestBloc destBloc;
    late TestResolver resolver;

    setUp(() {
      sourceBloc = SourceBloc();
      destBloc = DestBloc();
      resolver = TestResolver({
        SourceBloc: sourceBloc,
        DestBloc: destBloc,
      });
    });

    tearDown(() async {
      await resolver.disposeAll();
    });

    test('StateRelay transforms and forwards state changes', () async {
      final relay = StateRelay<SourceBloc, DestBloc, SourceState>(
        toEvent: (state) => UpdateMessageEvent(message: 'count: ${state.counter}'),
        resolver: resolver,
      );

      // Wait for async initialization
      await Future.delayed(const Duration(milliseconds: 100));

      // Send event to source bloc
      await sourceBloc.send(IncrementEvent());

      // Wait for relay to process
      await Future.delayed(const Duration(milliseconds: 100));

      // Verify dest bloc received transformed event
      expect(destBloc.state.message, 'count: 1');

      await relay.close();
    });

    test('StateRelay filters with when predicate', () async {
      final relay = StateRelay<SourceBloc, DestBloc, SourceState>(
        toEvent: (state) => UpdateMessageEvent(message: 'active: ${state.counter}'),
        when: (state) => state.isActive,
        resolver: resolver,
      );

      await Future.delayed(const Duration(milliseconds: 100));

      // Send event when not active - should not relay
      await sourceBloc.send(IncrementEvent());
      await Future.delayed(const Duration(milliseconds: 100));
      expect(destBloc.state.message, 'initial'); // Unchanged

      // Set active
      await sourceBloc.send(SetActiveEvent(active: true));
      await Future.delayed(const Duration(milliseconds: 100));
      expect(destBloc.state.message, 'active: 1'); // Now relayed

      // Another increment while active
      await sourceBloc.send(IncrementEvent());
      await Future.delayed(const Duration(milliseconds: 100));
      expect(destBloc.state.message, 'active: 2');

      // Set inactive
      await sourceBloc.send(SetActiveEvent(active: false));
      await Future.delayed(const Duration(milliseconds: 100));
      // Message updated to show the state when setActive event processed
      // but now isActive is false

      // Increment when not active - should not relay
      await sourceBloc.send(IncrementEvent());
      await Future.delayed(const Duration(milliseconds: 100));
      // Should not have updated to count: 3
      expect(destBloc.state.message.contains('3'), isFalse);

      await relay.close();
    });

    test('StateRelay closes cleanly', () async {
      final relay = StateRelay<SourceBloc, DestBloc, SourceState>(
        toEvent: (state) => UpdateMessageEvent(message: 'test'),
        resolver: resolver,
      );

      await Future.delayed(const Duration(milliseconds: 100));

      // Close should not throw
      await relay.close();
      expect(relay.isClosed, isTrue);

      // Multiple close calls should be safe
      await relay.close();
    });

    test('StateRelay stops relaying after close', () async {
      final relay = StateRelay<SourceBloc, DestBloc, SourceState>(
        toEvent: (state) => UpdateMessageEvent(message: 'count: ${state.counter}'),
        resolver: resolver,
      );

      await Future.delayed(const Duration(milliseconds: 100));

      // Initial relay works
      await sourceBloc.send(IncrementEvent());
      await Future.delayed(const Duration(milliseconds: 100));
      expect(destBloc.state.message, 'count: 1');

      // Close relay
      await relay.close();

      // Reset dest bloc state
      await destBloc.send(UpdateMessageEvent(message: 'reset'));
      await Future.delayed(const Duration(milliseconds: 50));

      // Send another event to source - should not relay
      await sourceBloc.send(IncrementEvent());
      await Future.delayed(const Duration(milliseconds: 100));

      // Dest should still be 'reset'
      expect(destBloc.state.message, 'reset');
    });

    test('StateRelay handles transformer error without closing', () async {
      int callCount = 0;

      final relay = StateRelay<SourceBloc, DestBloc, SourceState>(
        toEvent: (state) {
          callCount++;
          if (state.counter == 2) {
            throw Exception('Error on counter 2');
          }
          return UpdateMessageEvent(message: 'count: ${state.counter}');
        },
        resolver: resolver,
      );

      await Future.delayed(const Duration(milliseconds: 100));

      // First event should work
      await sourceBloc.send(IncrementEvent());
      await Future.delayed(const Duration(milliseconds: 100));
      expect(destBloc.state.message, 'count: 1');
      expect(callCount, 1);

      // Second event triggers error - relay should continue (not close)
      await sourceBloc.send(IncrementEvent());
      await Future.delayed(const Duration(milliseconds: 100));
      expect(callCount, 2);
      expect(destBloc.state.message, 'count: 1'); // Unchanged due to error

      // Third event should work again
      await sourceBloc.send(IncrementEvent());
      await Future.delayed(const Duration(milliseconds: 100));
      expect(callCount, 3);
      expect(destBloc.state.message, 'count: 3');

      expect(relay.isClosed, isFalse); // Relay still active

      await relay.close();
    });
  });

  group('StatusRelay Tests', () {
    late SourceBloc sourceBloc;
    late DestBloc destBloc;
    late TestResolver resolver;

    setUp(() {
      sourceBloc = SourceBloc();
      destBloc = DestBloc();
      resolver = TestResolver({
        SourceBloc: sourceBloc,
        DestBloc: destBloc,
      });
    });

    tearDown(() async {
      await resolver.disposeAll();
    });

    test('StatusRelay transforms and forwards StreamStatus', () async {
      final relay = StatusRelay<SourceBloc, DestBloc, SourceState>(
        toEvent: (status) {
          if (status is UpdatingStatus<SourceState>) {
            return UpdateMessageEvent(message: 'updating: ${status.state.counter}');
          }
          return UpdateMessageEvent(message: 'other status');
        },
        resolver: resolver,
      );

      await Future.delayed(const Duration(milliseconds: 100));

      await sourceBloc.send(IncrementEvent());
      await Future.delayed(const Duration(milliseconds: 100));

      expect(destBloc.state.message, 'updating: 1');

      await relay.close();
    });

    test('StatusRelay filters with when predicate on status', () async {
      final relay = StatusRelay<SourceBloc, DestBloc, SourceState>(
        toEvent: (status) => UpdateMessageEvent(message: 'count: ${status.state.counter}'),
        when: (status) => status is UpdatingStatus<SourceState>,
        resolver: resolver,
      );

      await Future.delayed(const Duration(milliseconds: 100));

      await sourceBloc.send(IncrementEvent());
      await Future.delayed(const Duration(milliseconds: 100));

      expect(destBloc.state.message, 'count: 1');

      await relay.close();
    });

    test('StatusRelay closes cleanly', () async {
      final relay = StatusRelay<SourceBloc, DestBloc, SourceState>(
        toEvent: (status) => UpdateMessageEvent(message: 'test'),
        resolver: resolver,
      );

      await Future.delayed(const Duration(milliseconds: 100));

      await relay.close();
      expect(relay.isClosed, isTrue);

      // Multiple close calls should be safe
      await relay.close();
    });

    test('StatusRelay stops relaying after close', () async {
      final relay = StatusRelay<SourceBloc, DestBloc, SourceState>(
        toEvent: (status) => UpdateMessageEvent(message: 'count: ${status.state.counter}'),
        resolver: resolver,
      );

      await Future.delayed(const Duration(milliseconds: 100));

      await sourceBloc.send(IncrementEvent());
      await Future.delayed(const Duration(milliseconds: 100));
      expect(destBloc.state.message, 'count: 1');

      await relay.close();

      await destBloc.send(UpdateMessageEvent(message: 'reset'));
      await Future.delayed(const Duration(milliseconds: 50));

      await sourceBloc.send(IncrementEvent());
      await Future.delayed(const Duration(milliseconds: 100));

      expect(destBloc.state.message, 'reset');
    });
  });

  group('StateRelay/StatusRelay Race Condition Tests', () {
    test('Close during initialization does not cause errors', () async {
      final sourceBloc = SourceBloc();
      final destBloc = DestBloc();
      final resolver = TestResolver({
        SourceBloc: sourceBloc,
        DestBloc: destBloc,
      });

      final relay = StateRelay<SourceBloc, DestBloc, SourceState>(
        toEvent: (state) => UpdateMessageEvent(message: 'test'),
        resolver: resolver,
      );

      // Immediately close before initialization completes
      await relay.close();

      // Wait for any pending microtasks
      await Future.delayed(const Duration(milliseconds: 100));

      await resolver.disposeAll();
    });

    test('Multiple StateRelays on same source work independently', () async {
      final sourceBloc = SourceBloc();
      final destBloc1 = DestBloc();
      final destBloc2 = DestBloc();

      final resolver1 = TestResolver({
        SourceBloc: sourceBloc,
        DestBloc: destBloc1,
      });
      final resolver2 = TestResolver({
        SourceBloc: sourceBloc,
        DestBloc: destBloc2,
      });

      final relay1 = StateRelay<SourceBloc, DestBloc, SourceState>(
        toEvent: (state) => UpdateMessageEvent(message: 'relay1: ${state.counter}'),
        resolver: resolver1,
      );

      final relay2 = StateRelay<SourceBloc, DestBloc, SourceState>(
        toEvent: (state) => UpdateMessageEvent(message: 'relay2: ${state.counter}'),
        resolver: resolver2,
      );

      await Future.delayed(const Duration(milliseconds: 100));

      await sourceBloc.send(IncrementEvent());
      await Future.delayed(const Duration(milliseconds: 100));

      expect(destBloc1.state.message, 'relay1: 1');
      expect(destBloc2.state.message, 'relay2: 1');

      await relay1.close();

      await sourceBloc.send(IncrementEvent());
      await Future.delayed(const Duration(milliseconds: 100));

      expect(destBloc1.state.message, 'relay1: 1'); // Unchanged
      expect(destBloc2.state.message, 'relay2: 2'); // Updated

      await relay2.close();
      await sourceBloc.close();
      await destBloc1.close();
      await destBloc2.close();
    });

    test('StateRelay handles dest bloc close gracefully', () async {
      final sourceBloc = SourceBloc();
      final destBloc = DestBloc();
      final resolver = TestResolver({
        SourceBloc: sourceBloc,
        DestBloc: destBloc,
      });

      final relay = StateRelay<SourceBloc, DestBloc, SourceState>(
        toEvent: (state) => UpdateMessageEvent(message: 'test'),
        resolver: resolver,
      );

      await Future.delayed(const Duration(milliseconds: 100));

      // Close dest bloc
      await destBloc.close();

      // Send event to source - relay should detect closed dest and close
      await sourceBloc.send(IncrementEvent());
      await Future.delayed(const Duration(milliseconds: 100));

      expect(relay.isClosed, isTrue);

      await sourceBloc.close();
    });

    test('StateRelay closes when source bloc closes', () async {
      final sourceBloc = SourceBloc();
      final destBloc = DestBloc();
      final resolver = TestResolver({
        SourceBloc: sourceBloc,
        DestBloc: destBloc,
      });

      final relay = StateRelay<SourceBloc, DestBloc, SourceState>(
        toEvent: (state) => UpdateMessageEvent(message: 'test'),
        resolver: resolver,
      );

      await Future.delayed(const Duration(milliseconds: 100));

      // Close source bloc
      await sourceBloc.close();
      await Future.delayed(const Duration(milliseconds: 100));

      expect(relay.isClosed, isTrue);

      await destBloc.close();
    });
  });
}
