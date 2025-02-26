import 'package:flutter_test/flutter_test.dart';
import 'package:juice/juice.dart';
import '../test_helpers.dart';

void main() {
//   group('StreamStatus Tests', () {
//     final state = TestState(value: 0);
//     final newState = TestState(value: 1);
//     final event = TestEvent();

//     test('StreamStatus.updating creates correct status', () {
//       final updating = StreamStatus<TestState>.updating(newState, state, event);

//       expect(updating.isUpdating, true);
//       expect(updating.isWaiting, false);
//       expect(updating.isFailure, false);
//       expect(updating.isCanceling, false);

//       expect(updating.state, newState);
//       expect(updating.oldState, state);
//       expect(updating.event, event);
//     });

//     test('StreamStatus.waiting creates correct status', () {
//       final waiting = StreamStatus<TestState>.waiting(newState, state, event);

//       expect(waiting.isUpdating, false);
//       expect(waiting.isWaiting, true);
//       expect(waiting.isFailure, false);
//       expect(waiting.isCanceling, false);

//       expect(waiting.state, newState);
//       expect(waiting.oldState, state);
//       expect(waiting.event, event);
//     });

//     test('StreamStatus.failure creates correct status', () {
//       final failure = StreamStatus<TestState>.failure(newState, state, event);

//       expect(failure.isUpdating, false);
//       expect(failure.isWaiting, false);
//       expect(failure.isFailure, true);
//       expect(failure.isCanceling, false);

//       expect(failure.state, newState);
//       expect(failure.oldState, state);
//       expect(failure.event, event);
//     });

//     test('StreamStatus.canceling creates correct status', () {
//       final canceling =
//           StreamStatus<TestState>.canceling(newState, state, event);

//       expect(canceling.isUpdating, false);
//       expect(canceling.isWaiting, false);
//       expect(canceling.isFailure, false);
//       expect(canceling.isCanceling, true);

//       expect(canceling.state, newState);
//       expect(canceling.oldState, state);
//       expect(canceling.event, event);
//     });

//     test('StreamStatus.copyWith creates a copy with correct properties', () {
//       final updating = StreamStatus<TestState>.updating(state, state, event);
//       final copied = updating.copyWith(
//         newState: newState,
//         event: TestEvent(groups: {"new-group"}),
//       );

//       expect(copied.isUpdating, true); // Status remains the same
//       expect(copied.state, newState); // State updated
//       expect(copied.event?.groupsToRebuild,
//           contains("new-group")); // Event updated
//     });

//     test('StreamStatus.copyWithStatus changes status', () {
//       final updating = StreamStatus<TestState>.updating(state, state, event);

//       final waiting = updating.copyWithStatus(StreamStatusType.waiting);
//       expect(waiting.isWaiting, true);

//       final failure = updating.copyWithStatus(StreamStatusType.failure);
//       expect(failure.isFailure, true);

//       final canceling = updating.copyWithStatus(StreamStatusType.canceling);
//       expect(canceling.isCanceling, true);

//       final backToUpdating = waiting.copyWithStatus(StreamStatusType.updating);
//       expect(backToUpdating.isUpdating, true);
//     });

//     test('isStateTypeOf checks state type correctly', () {
//       final status = StreamStatus<TestState>.updating(state, state, event);

//       expect(status.isStateTypeOf<TestState>(), true);
//       expect(status.isStateTypeOf<SecondTestState>(), false);
//     });

//     test('When status types match typesafe helper methods', () {
//       final waiting = StreamStatus<TestState>.waiting(state, state, event);

//       expect(waiting.isWaitingFor<TestState>(), true);
//       expect(waiting.isWaitingFor<SecondTestState>(), false);

//       final failure = StreamStatus<TestState>.failure(state, state, event);

//       expect(failure.isFailureFor<TestState>(), true);
//       expect(failure.isFailureFor<SecondTestState>(), false);
//     });
//   });
}
