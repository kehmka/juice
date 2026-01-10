// ignore_for_file: deprecated_member_use_from_same_package

import 'package:flutter_test/flutter_test.dart';
import 'package:juice/juice.dart';

// Test States
class RelaySourceState extends BlocState {
  final int counter;
  final bool isLoading;
  RelaySourceState({required this.counter, this.isLoading = false});
  RelaySourceState copyWith({int? counter, bool? isLoading}) =>
      RelaySourceState(
        counter: counter ?? this.counter,
        isLoading: isLoading ?? this.isLoading,
      );
}

class RelayDestState extends BlocState {
  final String lastValue;
  RelayDestState({required this.lastValue});
  RelayDestState copyWith({String? lastValue}) =>
      RelayDestState(lastValue: lastValue ?? this.lastValue);
}

// Test Events
class IncrementSourceEvent extends EventBase {}

class UpdateDestEvent extends EventBase {
  final String value;
  UpdateDestEvent({required this.value});
}

// Test Use Cases
class IncrementSourceUseCase
    extends BlocUseCase<RelaySourceBloc, IncrementSourceEvent> {
  @override
  Future<void> execute(IncrementSourceEvent event) async {
    emitUpdate(
      newState: bloc.state.copyWith(counter: bloc.state.counter + 1),
      groupsToRebuild: {'counter'},
    );
  }
}

class UpdateDestUseCase extends BlocUseCase<RelayDestBloc, UpdateDestEvent> {
  @override
  Future<void> execute(UpdateDestEvent event) async {
    emitUpdate(
      newState: bloc.state.copyWith(lastValue: event.value),
      groupsToRebuild: {'dest'},
    );
  }
}

// Test Blocs
class RelaySourceBloc extends JuiceBloc<RelaySourceState> {
  RelaySourceBloc()
      : super(
          RelaySourceState(counter: 0),
          [
            () => UseCaseBuilder(
                  typeOfEvent: IncrementSourceEvent,
                  useCaseGenerator: () => IncrementSourceUseCase(),
                ),
          ],
          [],
        );
}

class RelayDestBloc extends JuiceBloc<RelayDestState> {
  RelayDestBloc()
      : super(
          RelayDestState(lastValue: 'initial'),
          [
            () => UseCaseBuilder(
                  typeOfEvent: UpdateDestEvent,
                  useCaseGenerator: () => UpdateDestUseCase(),
                ),
          ],
          [],
        );
}

// Test resolver
class RelayTestResolver implements BlocDependencyResolver {
  final Map<Type, JuiceBloc> blocs;

  RelayTestResolver(this.blocs);

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
  group('RelayUseCaseBuilder Tests', () {
    late RelaySourceBloc sourceBloc;
    late RelayDestBloc destBloc;
    late RelayTestResolver resolver;

    setUp(() {
      sourceBloc = RelaySourceBloc();
      destBloc = RelayDestBloc();
      resolver = RelayTestResolver({
        RelaySourceBloc: sourceBloc,
        RelayDestBloc: destBloc,
      });
    });

    tearDown(() async {
      await resolver.disposeAll();
    });

    test('RelayUseCaseBuilder transforms and forwards state changes', () async {
      final relay =
          RelayUseCaseBuilder<RelaySourceBloc, RelayDestBloc, RelaySourceState>(
        typeOfEvent: UpdateDestEvent,
        statusToEventTransformer: (status) {
          final state = status.state;
          return UpdateDestEvent(value: 'counter: ${state.counter}');
        },
        useCaseGenerator: () => UpdateDestUseCase(),
        resolver: resolver,
      );

      // Wait for async initialization
      await Future.delayed(const Duration(milliseconds: 100));

      // Send event to source bloc
      await sourceBloc.send(IncrementSourceEvent());

      // Wait for relay to process
      await Future.delayed(const Duration(milliseconds: 100));

      // Verify dest bloc received transformed event
      expect(destBloc.state.lastValue, 'counter: 1');

      await relay.close();
    });

    test('RelayUseCaseBuilder closes cleanly', () async {
      final relay =
          RelayUseCaseBuilder<RelaySourceBloc, RelayDestBloc, RelaySourceState>(
        typeOfEvent: UpdateDestEvent,
        statusToEventTransformer: (status) => UpdateDestEvent(value: 'test'),
        useCaseGenerator: () => UpdateDestUseCase(),
        resolver: resolver,
      );

      await Future.delayed(const Duration(milliseconds: 100));

      // Close should not throw
      await relay.close();

      // Multiple close calls should be safe
      await relay.close();
    });

    test('RelayUseCaseBuilder stops relaying after close', () async {
      final relay =
          RelayUseCaseBuilder<RelaySourceBloc, RelayDestBloc, RelaySourceState>(
        typeOfEvent: UpdateDestEvent,
        statusToEventTransformer: (status) =>
            UpdateDestEvent(value: 'counter: ${status.state.counter}'),
        useCaseGenerator: () => UpdateDestUseCase(),
        resolver: resolver,
      );

      await Future.delayed(const Duration(milliseconds: 100));

      // Initial relay works
      await sourceBloc.send(IncrementSourceEvent());
      await Future.delayed(const Duration(milliseconds: 100));
      expect(destBloc.state.lastValue, 'counter: 1');

      // Close relay
      await relay.close();

      // Reset dest bloc state
      await destBloc.send(UpdateDestEvent(value: 'reset'));
      await Future.delayed(const Duration(milliseconds: 50));
      expect(destBloc.state.lastValue, 'reset');

      // Send another event to source - should not relay
      await sourceBloc.send(IncrementSourceEvent());
      await Future.delayed(const Duration(milliseconds: 100));

      // Dest should still be 'reset', not updated
      expect(destBloc.state.lastValue, 'reset');
    });
  });

  group('RelayUseCaseBuilder Error Handling Tests', () {
    late RelaySourceBloc sourceBloc;
    late RelayDestBloc destBloc;
    late RelayTestResolver resolver;

    setUp(() {
      sourceBloc = RelaySourceBloc();
      destBloc = RelayDestBloc();
      resolver = RelayTestResolver({
        RelaySourceBloc: sourceBloc,
        RelayDestBloc: destBloc,
      });
    });

    tearDown(() async {
      await resolver.disposeAll();
    });

    test('Relay closes when source bloc closes', () async {
      final relay =
          RelayUseCaseBuilder<RelaySourceBloc, RelayDestBloc, RelaySourceState>(
        typeOfEvent: UpdateDestEvent,
        statusToEventTransformer: (status) => UpdateDestEvent(value: 'test'),
        useCaseGenerator: () => UpdateDestUseCase(),
        resolver: resolver,
      );

      await Future.delayed(const Duration(milliseconds: 100));

      // Close source bloc
      await sourceBloc.close();

      // Wait for relay to handle close
      await Future.delayed(const Duration(milliseconds: 100));

      // Clean up relay (should be no-op since already closed)
      await relay.close();
    });

    test('Relay handles transformer error gracefully', () async {
      int relayCount = 0;

      final relay =
          RelayUseCaseBuilder<RelaySourceBloc, RelayDestBloc, RelaySourceState>(
        typeOfEvent: UpdateDestEvent,
        statusToEventTransformer: (status) {
          relayCount++;
          if (status.state.counter == 2) {
            throw Exception('Error on counter 2');
          }
          return UpdateDestEvent(value: 'counter: ${status.state.counter}');
        },
        useCaseGenerator: () => UpdateDestUseCase(),
        resolver: resolver,
      );

      await Future.delayed(const Duration(milliseconds: 100));

      // First event should work
      await sourceBloc.send(IncrementSourceEvent());
      await Future.delayed(const Duration(milliseconds: 100));
      expect(destBloc.state.lastValue, 'counter: 1');
      expect(relayCount, 1);

      // Second event triggers error - relay should close
      await sourceBloc.send(IncrementSourceEvent());
      await Future.delayed(const Duration(milliseconds: 100));

      // Relay attempted to process but errored
      expect(relayCount, 2);

      // Dest should still have old value (error prevented update)
      expect(destBloc.state.lastValue, 'counter: 1');

      await relay.close();
    });

    test('Relay handles dest bloc close gracefully', () async {
      final relay =
          RelayUseCaseBuilder<RelaySourceBloc, RelayDestBloc, RelaySourceState>(
        typeOfEvent: UpdateDestEvent,
        statusToEventTransformer: (status) => UpdateDestEvent(value: 'test'),
        useCaseGenerator: () => UpdateDestUseCase(),
        resolver: resolver,
      );

      await Future.delayed(const Duration(milliseconds: 100));

      // Close dest bloc
      await destBloc.close();

      // Send event to source - relay should detect closed dest and close
      await sourceBloc.send(IncrementSourceEvent());

      // Wait for relay to handle
      await Future.delayed(const Duration(milliseconds: 100));

      // Clean up
      await relay.close();
    });
  });

  group('RelayUseCaseBuilder Race Condition Tests', () {
    test('Close during initialization does not cause errors', () async {
      final sourceBloc = RelaySourceBloc();
      final destBloc = RelayDestBloc();
      final resolver = RelayTestResolver({
        RelaySourceBloc: sourceBloc,
        RelayDestBloc: destBloc,
      });

      final relay =
          RelayUseCaseBuilder<RelaySourceBloc, RelayDestBloc, RelaySourceState>(
        typeOfEvent: UpdateDestEvent,
        statusToEventTransformer: (status) => UpdateDestEvent(value: 'test'),
        useCaseGenerator: () => UpdateDestUseCase(),
        resolver: resolver,
      );

      // Immediately close before initialization completes
      await relay.close();

      // Wait for any pending microtasks
      await Future.delayed(const Duration(milliseconds: 100));

      // Clean up
      await resolver.disposeAll();
    });

    test('Multiple relays on same source bloc work independently', () async {
      final sourceBloc = RelaySourceBloc();
      final destBloc1 = RelayDestBloc();
      final destBloc2 = RelayDestBloc();

      final resolver1 = RelayTestResolver({
        RelaySourceBloc: sourceBloc,
        RelayDestBloc: destBloc1,
      });
      final resolver2 = RelayTestResolver({
        RelaySourceBloc: sourceBloc,
        RelayDestBloc: destBloc2,
      });

      final relay1 =
          RelayUseCaseBuilder<RelaySourceBloc, RelayDestBloc, RelaySourceState>(
        typeOfEvent: UpdateDestEvent,
        statusToEventTransformer: (status) =>
            UpdateDestEvent(value: 'relay1: ${status.state.counter}'),
        useCaseGenerator: () => UpdateDestUseCase(),
        resolver: resolver1,
      );

      final relay2 =
          RelayUseCaseBuilder<RelaySourceBloc, RelayDestBloc, RelaySourceState>(
        typeOfEvent: UpdateDestEvent,
        statusToEventTransformer: (status) =>
            UpdateDestEvent(value: 'relay2: ${status.state.counter}'),
        useCaseGenerator: () => UpdateDestUseCase(),
        resolver: resolver2,
      );

      await Future.delayed(const Duration(milliseconds: 100));

      // Send event to source
      await sourceBloc.send(IncrementSourceEvent());
      await Future.delayed(const Duration(milliseconds: 100));

      // Both dest blocs should receive updates
      expect(destBloc1.state.lastValue, 'relay1: 1');
      expect(destBloc2.state.lastValue, 'relay2: 1');

      // Close one relay
      await relay1.close();

      // Send another event
      await sourceBloc.send(IncrementSourceEvent());
      await Future.delayed(const Duration(milliseconds: 100));

      // Only destBloc2 should update
      expect(destBloc1.state.lastValue, 'relay1: 1'); // Still old value
      expect(destBloc2.state.lastValue, 'relay2: 2'); // Updated

      await relay2.close();
      await sourceBloc.close();
      await destBloc1.close();
      await destBloc2.close();
    });
  });
}
