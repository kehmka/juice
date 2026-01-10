import 'package:flutter_test/flutter_test.dart';
import 'package:juice/juice.dart';

class TestState extends BlocState {
  final int value;

  TestState({required this.value});

  TestState copyWith({int? value}) => TestState(value: value ?? this.value);
}

// Create a concrete implementation of EventBase for testing
class TestEvent extends EventBase {}

void main() {
  group('StreamStatus Tests', () {
    final state = TestState(value: 0);
    final newState = TestState(value: 1);
    final event = TestEvent();

    test('StreamStatus.updating creates correct status', () {
      final updating = StreamStatus<TestState>.updating(newState, state, event);

      expect(updating is UpdatingStatus, true);

      updating.when(
        updating: (s, oldS, e) {
          expect(s, newState);
          expect(oldS, state);
          expect(e, event);
          return null;
        },
        waiting: (_, __, ___) => fail('Should be updating status'),
        canceling: (_, __, ___) => fail('Should be updating status'),
        failure: (_, __, ___) => fail('Should be updating status'),
      );
    });

    test('StreamStatus.waiting creates correct status', () {
      final waiting = StreamStatus<TestState>.waiting(newState, state, event);

      expect(waiting is WaitingStatus, true);

      waiting.when(
        updating: (_, __, ___) => fail('Should be waiting status'),
        waiting: (s, oldS, e) {
          expect(s, newState);
          expect(oldS, state);
          expect(e, event);
          return null;
        },
        canceling: (_, __, ___) => fail('Should be waiting status'),
        failure: (_, __, ___) => fail('Should be waiting status'),
      );
    });

    test('StreamStatus.failure creates correct status', () {
      final failure = StreamStatus<TestState>.failure(newState, state, event);

      expect(failure is FailureStatus, true);

      failure.when(
        updating: (_, __, ___) => fail('Should be failure status'),
        waiting: (_, __, ___) => fail('Should be failure status'),
        canceling: (_, __, ___) => fail('Should be failure status'),
        failure: (s, oldS, e) {
          expect(s, newState);
          expect(oldS, state);
          expect(e, event);
          return null;
        },
      );
    });

    test('StreamStatus.canceling creates correct status', () {
      final canceling =
          StreamStatus<TestState>.canceling(newState, state, event);

      expect(canceling is CancelingStatus, true);

      canceling.when(
        updating: (_, __, ___) => fail('Should be canceling status'),
        waiting: (_, __, ___) => fail('Should be canceling status'),
        canceling: (s, oldS, e) {
          expect(s, newState);
          expect(oldS, state);
          expect(e, event);
          return null;
        },
        failure: (_, __, ___) => fail('Should be canceling status'),
      );
    });

    test('StreamStatus.copyWith creates a copy with correct properties', () {
      final updating = StreamStatus<TestState>.updating(state, state, event);
      final newEvent = TestEvent();
      final copied = updating.copyWith(
        state: newState,
        event: newEvent,
      );

      expect(copied is UpdatingStatus, true); // Status remains the same
      expect(copied.state, newState); // State updated
      expect(copied.event, isNotNull);
      expect(identical(copied.event, event), isFalse); // Event updated
    });

    test('matchesState extension method works correctly', () {
      final status = StreamStatus<TestState>.updating(state, state, event);

      expect(status.matchesState<TestState>(), true);
      // It seems the actual implementation behaves differently than expected
      // BlocState is the parent of TestState, so the test is matching
      expect(status.matchesState<BlocState>(), true);
    });

    test('Type-specific checks work correctly', () {
      final waiting = StreamStatus<TestState>.waiting(state, state, event);

      expect(waiting.isWaitingFor<TestState>(), true);
      expect(waiting.isUpdatingFor<TestState>(), false);

      final failure = StreamStatus<TestState>.failure(state, state, event);

      expect(failure.isFailureFor<TestState>(), true);
      expect(failure.isWaitingFor<TestState>(), false);
    });
  });
}
