import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice/juice.dart';

// Test state
class CounterState extends BlocState {
  final int count;
  final String? message;

  CounterState({this.count = 0, this.message});

  CounterState copyWith({int? count, String? message}) => CounterState(
      count: count ?? this.count, message: message ?? this.message);

  @override
  String toString() => 'CounterState(count: $count, message: $message)';
}

// Test events
class IncrementEvent extends EventBase {}

class DecrementEvent extends EventBase {}

class SetCountEvent extends EventBase {
  final int value;
  SetCountEvent(this.value);
}

class AsyncEvent extends EventBase {}

class FailingEvent extends EventBase {}

// Type-safe groups for testing
abstract class CounterGroups {
  static const counter = RebuildGroup('counter');
  static const message = RebuildGroup('message');
}

// Enum groups for testing
enum TestGroups { counter, message, all }

// Test bloc with inline use cases
class InlineCounterBloc extends JuiceBloc<CounterState> {
  InlineCounterBloc()
      : super(CounterState(), [
          // Simple increment
          () => InlineUseCaseBuilder<InlineCounterBloc, CounterState,
                  IncrementEvent>(
                typeOfEvent: IncrementEvent,
                handler: (ctx, event) async {
                  ctx.emit.update(
                    newState: ctx.state.copyWith(count: ctx.state.count + 1),
                    groups: {CounterGroups.counter},
                  );
                },
              ),

          // Simple decrement
          () => InlineUseCaseBuilder<InlineCounterBloc, CounterState,
                  DecrementEvent>(
                typeOfEvent: DecrementEvent,
                handler: (ctx, event) async {
                  ctx.emit.update(
                    newState: ctx.state.copyWith(count: ctx.state.count - 1),
                    groups: {CounterGroups.counter},
                  );
                },
              ),

          // Set count with event parameter
          () => InlineUseCaseBuilder<InlineCounterBloc, CounterState,
                  SetCountEvent>(
                typeOfEvent: SetCountEvent,
                handler: (ctx, event) async {
                  ctx.emit.update(
                    newState: ctx.state.copyWith(count: event.value),
                    groups: {CounterGroups.counter},
                  );
                },
              ),

          // Async operation with waiting state
          () =>
              InlineUseCaseBuilder<InlineCounterBloc, CounterState, AsyncEvent>(
                typeOfEvent: AsyncEvent,
                handler: (ctx, event) async {
                  ctx.emit.waiting(
                    newState: ctx.state.copyWith(message: 'Loading...'),
                    groups: {CounterGroups.message},
                  );

                  await Future.delayed(Duration(milliseconds: 10));

                  ctx.emit.update(
                    newState: ctx.state.copyWith(
                      count: ctx.state.count + 10,
                      message: 'Done!',
                    ),
                    groups: {CounterGroups.counter, CounterGroups.message},
                  );
                },
              ),

          // Failing operation
          () => InlineUseCaseBuilder<InlineCounterBloc, CounterState,
                  FailingEvent>(
                typeOfEvent: FailingEvent,
                handler: (ctx, event) async {
                  ctx.emit.failure(
                    newState: ctx.state.copyWith(message: 'Failed!'),
                    groups: {CounterGroups.message},
                  );
                },
              ),
        ]);
}

void main() {
  group('InlineUseCaseBuilder', () {
    late InlineCounterBloc bloc;

    setUp(() {
      bloc = InlineCounterBloc();
    });

    tearDown(() async {
      await bloc.close();
    });

    test('handles simple increment event', () async {
      expect(bloc.state.count, 0);

      await bloc.send(IncrementEvent());
      await Future.delayed(Duration(milliseconds: 10));

      expect(bloc.state.count, 1);
    });

    test('handles simple decrement event', () async {
      expect(bloc.state.count, 0);

      await bloc.send(DecrementEvent());
      await Future.delayed(Duration(milliseconds: 10));

      expect(bloc.state.count, -1);
    });

    test('handles event with parameter', () async {
      expect(bloc.state.count, 0);

      await bloc.send(SetCountEvent(42));
      await Future.delayed(Duration(milliseconds: 10));

      expect(bloc.state.count, 42);
    });

    test('handles multiple events in sequence', () async {
      expect(bloc.state.count, 0);

      await bloc.send(IncrementEvent());
      await bloc.send(IncrementEvent());
      await bloc.send(IncrementEvent());
      await Future.delayed(Duration(milliseconds: 10));

      expect(bloc.state.count, 3);
    });

    test('emits waiting then update for async operations', () async {
      final statuses = <StreamStatus<CounterState>>[];
      final subscription = bloc.stream.listen(statuses.add);

      await bloc.send(AsyncEvent());
      await Future.delayed(Duration(milliseconds: 50));

      await subscription.cancel();

      // Should have waiting then updating
      expect(statuses.length, greaterThanOrEqualTo(2));
      expect(statuses.any((s) => s is WaitingStatus), isTrue);
      expect(statuses.last, isA<UpdatingStatus>());
      expect(bloc.state.count, 10);
      expect(bloc.state.message, 'Done!');
    });

    test('emits failure status', () async {
      final statuses = <StreamStatus<CounterState>>[];
      final subscription = bloc.stream.listen(statuses.add);

      await bloc.send(FailingEvent());
      await Future.delayed(Duration(milliseconds: 10));

      await subscription.cancel();

      expect(statuses.any((s) => s is FailureStatus), isTrue);
      expect(bloc.state.message, 'Failed!');
    });

    test('provides typed state access', () async {
      // This test verifies that ctx.state returns CounterState, not BlocState
      // If types were wrong, this wouldn't compile
      await bloc.send(SetCountEvent(100));
      await Future.delayed(Duration(milliseconds: 10));

      expect(bloc.state.count, 100);
    });

    test('provides access to oldState', () async {
      await bloc.send(SetCountEvent(50));
      await Future.delayed(Duration(milliseconds: 10));

      expect(bloc.state.count, 50);
      expect(bloc.oldState.count, 0);
    });
  });

  group('InlineEmitter groups conversion', () {
    test('converts RebuildGroup to string', () async {
      final bloc = InlineCounterBloc();
      final events = <EventBase?>[];

      bloc.stream.listen((status) {
        events.add(status.event);
      });

      await bloc.send(IncrementEvent());
      await Future.delayed(Duration(milliseconds: 10));

      expect(events.isNotEmpty, isTrue);
      expect(events.last?.groupsToRebuild, contains('counter'));

      await bloc.close();
    });

    test('converts enum to string', () async {
      // Create a bloc with enum groups
      final bloc = _EnumGroupBloc();

      final events = <EventBase?>[];
      bloc.stream.listen((status) {
        events.add(status.event);
      });

      await bloc.send(IncrementEvent());
      await Future.delayed(Duration(milliseconds: 10));

      expect(events.isNotEmpty, isTrue);
      expect(events.last?.groupsToRebuild, contains('counter'));

      await bloc.close();
    });

    test('passes string groups unchanged', () async {
      final bloc = _StringGroupBloc();

      final events = <EventBase?>[];
      bloc.stream.listen((status) {
        events.add(status.event);
      });

      await bloc.send(IncrementEvent());
      await Future.delayed(Duration(milliseconds: 10));

      expect(events.isNotEmpty, isTrue);
      expect(events.last?.groupsToRebuild, contains('my-group'));

      await bloc.close();
    });
  });

  group('InlineContext', () {
    test('provides bloc access', () async {
      bool blocAccessed = false;

      final bloc = _ContextTestBloc(onExecute: (ctx) {
        blocAccessed = ctx.bloc is JuiceBloc;
      });

      await bloc.send(IncrementEvent());
      await Future.delayed(Duration(milliseconds: 10));

      expect(blocAccessed, isTrue);

      await bloc.close();
    });

    test('provides typed state', () async {
      int? stateCount;

      final bloc = _ContextTestBloc(onExecute: (ctx) {
        // This proves ctx.state is CounterState, not BlocState
        stateCount = ctx.state.count;
      });

      await bloc.send(IncrementEvent());
      await Future.delayed(Duration(milliseconds: 10));

      expect(stateCount, 0);

      await bloc.close();
    });
  });
}

// Helper bloc for enum group testing
class _EnumGroupBloc extends JuiceBloc<CounterState> {
  _EnumGroupBloc()
      : super(CounterState(), [
          () => InlineUseCaseBuilder<_EnumGroupBloc, CounterState,
                  IncrementEvent>(
                typeOfEvent: IncrementEvent,
                handler: (ctx, event) async {
                  ctx.emit.update(
                    newState: ctx.state.copyWith(count: ctx.state.count + 1),
                    groups: {TestGroups.counter}, // Enum group
                  );
                },
              ),
        ]);
}

// Helper bloc for string group testing
class _StringGroupBloc extends JuiceBloc<CounterState> {
  _StringGroupBloc()
      : super(CounterState(), [
          () => InlineUseCaseBuilder<_StringGroupBloc, CounterState,
                  IncrementEvent>(
                typeOfEvent: IncrementEvent,
                handler: (ctx, event) async {
                  ctx.emit.update(
                    newState: ctx.state.copyWith(count: ctx.state.count + 1),
                    groups: {'my-group'}, // String group
                  );
                },
              ),
        ]);
}

// Helper bloc for context testing
class _ContextTestBloc extends JuiceBloc<CounterState> {
  _ContextTestBloc(
      {required void Function(InlineContext<_ContextTestBloc, CounterState>)
          onExecute})
      : super(CounterState(), [
          () => InlineUseCaseBuilder<_ContextTestBloc, CounterState,
                  IncrementEvent>(
                typeOfEvent: IncrementEvent,
                handler: (ctx, event) async {
                  onExecute(ctx);
                  ctx.emit.update(
                    newState: ctx.state.copyWith(count: ctx.state.count + 1),
                  );
                },
              ),
        ]);
}
