import 'package:flutter_test/flutter_test.dart';
import 'package:juice/juice.dart';
import '../test_helpers.dart';

void main() {
  group('StreamStatus Tests', () {
    final state = TestState(value: 0);
    final newState = TestState(value: 1);
    final event = TestEvent();

    test('StreamStatus.updating creates correct status', () {
      final updating = StreamStatus<TestState>.updating(newState, state, event);

      expect(updating.isWaitingFor(), false);
      expect(updating.isCancelingFor(), false);
      expect(updating.isFailureFor(), false);
      expect(updating.isUpdatingFor(), true);

      expect(updating.state, newState);
      expect(updating.oldState, state);
      expect(updating.event, event);
    });

    test('StreamStatus.waiting creates correct status', () {
      final waiting = StreamStatus<TestState>.waiting(newState, state, event);

      expect(waiting.isWaitingFor(), true);
      expect(waiting.isCancelingFor(), false);
      expect(waiting.isFailureFor(), false);
      expect(waiting.isUpdatingFor(), false);

      expect(waiting.state, newState);
      expect(waiting.oldState, state);
      expect(waiting.event, event);
    });

    test('StreamStatus.failure creates correct status', () {
      final failure = StreamStatus<TestState>.failure(newState, state, event);

      expect(failure.isUpdatingFor(), false);
      expect(failure.isWaitingFor(), false);
      expect(failure.isFailureFor(), true);
      expect(failure.isCancelingFor(), false);

      expect(failure.state, newState);
      expect(failure.oldState, state);
      expect(failure.event, event);
    });

    test('StreamStatus.canceling creates correct status', () {
      final canceling =
          StreamStatus<TestState>.canceling(newState, state, event);

      expect(canceling.isUpdatingFor(), false);
      expect(canceling.isWaitingFor(), false);
      expect(canceling.isFailureFor(), false);
      expect(canceling.isCancelingFor(), true);

      expect(canceling.state, newState);
      expect(canceling.oldState, state);
      expect(canceling.event, event);
    });

    test('StreamStatus.copyWith creates a copy with correct properties', () {
      final updating = StreamStatus<TestState>.updating(state, state, event);
      final copied = updating.copyWith(
        state: newState,
        oldState: state,
        event: TestEvent(groups: {"new-group"}),
      );

      expect(copied.isUpdatingFor(), true); // Status remains the same
      expect(copied.state, newState); // State updated
      expect(copied.event?.groupsToRebuild,
          contains("new-group")); // Event updated
    });

    test('isStateTypeOf checks state type correctly', () {
      final status = StreamStatus<TestState>.updating(state, state, event);

      expect(status is UpdatingStatus, true);
      expect(status.state is SecondTestState, false);
    });

    test('When status types match typesafe helper methods', () {
      final waiting = StreamStatus<TestState>.waiting(state, state, event);

      expect(waiting.isWaitingFor<TestState>(), true);
      expect(waiting.isWaitingFor<SecondTestState>(), false);

      final failure = StreamStatus<TestState>.failure(state, state, event);

      expect(failure.isFailureFor<TestState>(), true);
      expect(failure.isFailureFor<SecondTestState>(), false);
    });
  });
}
