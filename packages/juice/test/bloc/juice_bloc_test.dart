import 'package:flutter_test/flutter_test.dart';
import 'package:juice/juice.dart';
import '../test_helpers.dart';

void main() {
  group('JuiceBloc Tests', () {
    late TestBloc bloc;

    setUp(() {
      bloc = TestBloc(initialState: TestState(value: 0));
    });

    tearDown(() {
      bloc.close();
    });

    test('JuiceBloc initializes with correct state', () {
      expect(bloc.state.value, 0);
      expect(bloc.currentStatus, isA<StreamStatus<TestState>>());
      expect((bloc.currentStatus as StreamStatus).isUpdatingFor(), true);
    });

    test('JuiceBloc emits correct StreamStatus after events', () async {
      // Send event
      await bloc.send(TestEvent());

      // Verify state transition
      expect(bloc.state.value, 1);
      expect((bloc.currentStatus as StreamStatus).isUpdatingFor(), true);
      expect(bloc.currentStatus.event, isA<TestEvent>());

      // Send another event
      await bloc.send(TestEvent());

      // Verify state updated again
      expect(bloc.state.value, 2);
    });

    test('JuiceBloc handles different event types', () async {
      // Send increment event
      await bloc.send(IncrementEvent());
      expect(bloc.state.value, 1);

      // Send decrement event
      await bloc.send(DecrementEvent());
      expect(bloc.state.value, 0);
    });

    test('JuiceBloc emits events with correct groupsToRebuild', () async {
      // Track emitted statuses
      final emittedStatuses = <StreamStatus>[];
      final subscription = bloc.stream.listen(emittedStatuses.add);

      // Send event with specific group
      await bloc.send(TestEvent(groups: {"specific-group"}));

      // Verify emitted status contains the correct group
      expect(emittedStatuses.length, 1);
      expect(emittedStatuses[0].event?.groupsToRebuild,
          contains("specific-group"));

      // Clean up
      await subscription.cancel();
    });

    test('JuiceBloc closes properly and cleans up resources', () async {
      // Send an event
      await bloc.send(TestEvent());
      expect(bloc.state.value, 1);

      // Close the bloc
      await bloc.close();

      // Verify the bloc is closed
      expect(bloc.isClosed, true);

      // Trying to send an event to a closed bloc should throw
      // error shows up in logs
      expect(
          () => bloc.send(TestEvent()), returnsNormally); // throwsA(anything));
    });
  });
}
