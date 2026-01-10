import 'package:flutter_test/flutter_test.dart';
import 'package:juice/juice.dart';
import '../test_helpers.dart';

void main() {
  group('BlocUseCase Tests', () {
    late TestBloc bloc;
    late TestUseCase useCase;

    setUp(() {
      bloc = TestBloc(initialState: TestState(value: 0));
      useCase = TestUseCase();
      useCase.bloc = bloc;

      // Set up emitter functions that the test use case needs
      useCase.emitUpdate = (
          {newState,
          aviatorName,
          aviatorArgs,
          groupsToRebuild,
          bool skipIfSame = false}) {
        bloc.emit(StreamStatus.updating(
          newState as TestState? ?? bloc.state,
          bloc.state,
          TestEvent(groups: groupsToRebuild),
        ));
      };

      useCase.emitWaiting =
          ({newState, aviatorName, aviatorArgs, groupsToRebuild}) {
        bloc.emit(StreamStatus.waiting(
          newState as TestState? ?? bloc.state,
          bloc.state,
          TestEvent(groups: groupsToRebuild),
        ));
      };

      useCase.emitFailure = (
          {newState,
          aviatorName,
          aviatorArgs,
          groupsToRebuild,
          Object? error,
          StackTrace? errorStackTrace}) {
        bloc.emit(StreamStatus.failure(
          newState as TestState? ?? bloc.state,
          bloc.state,
          TestEvent(groups: groupsToRebuild),
          error: error,
          errorStackTrace: errorStackTrace,
        ));
      };

      useCase.emitCancel =
          ({newState, aviatorName, aviatorArgs, groupsToRebuild}) {
        bloc.emit(StreamStatus.canceling(
          newState as TestState? ?? bloc.state,
          bloc.state,
          TestEvent(groups: groupsToRebuild),
        ));
      };

      useCase.emitEvent = ({EventBase? event}) {
        if (event != null) {
          bloc.send(event);
        }
      };
    });

    tearDown(() {
      bloc.close();
    });

    test('BlocUseCase executes and updates state correctly', () async {
      // Execute use case
      await useCase.execute(TestEvent());

      // Verify state updated
      expect(bloc.state.value, 1);
    });

    test('BlocUseCase updates state with correct group', () async {
      // Track emitted statuses
      final emittedStatuses = <StreamStatus>[];
      final subscription = bloc.stream.listen(emittedStatuses.add);

      // Execute use case
      await useCase.execute(TestEvent());

      // Verify emitted status contains the correct group
      expect(emittedStatuses.length, 1);
      expect(emittedStatuses[0].event?.groupsToRebuild, contains("test-group"));

      // Clean up
      await subscription.cancel();
    });

    test('emitWaiting emits correct status', () async {
      // Replace emitUpdate with mock function to track calls
      bool updateCalled = false;
      useCase.emitUpdate = (
          {newState,
          aviatorName,
          aviatorArgs,
          groupsToRebuild,
          bool skipIfSame = false}) {
        updateCalled = true;
      };

      // Track emitted statuses
      final emittedStatuses = <StreamStatus>[];
      final subscription = bloc.stream.listen(emittedStatuses.add);

      // Create custom use case with waiting
      final waitingUseCase = CustomWaitingUseCase();
      waitingUseCase.bloc = bloc;

      // Set up all emitter functions
      waitingUseCase.emitWaiting =
          ({newState, aviatorName, aviatorArgs, groupsToRebuild}) {
        bloc.emit(StreamStatus.waiting(
          newState as TestState? ?? bloc.state,
          bloc.state,
          TestEvent(groups: groupsToRebuild),
        ));
      };
      waitingUseCase.emitUpdate = useCase.emitUpdate;
      waitingUseCase.emitCancel = useCase.emitCancel;
      waitingUseCase.emitFailure = useCase.emitFailure;
      waitingUseCase.emitEvent = useCase.emitEvent;

      // Execute use case with waiting
      await waitingUseCase.execute(TestEvent());

      // Verify waiting status was emitted
      expect(emittedStatuses.length, 1);
      expect(emittedStatuses[0] is WaitingStatus, true);
      expect(updateCalled, false); // emitUpdate not called

      // Clean up
      await subscription.cancel();
    });

    test('emitFailure emits correct status', () async {
      // Replace emitUpdate with mock function to track calls
      bool updateCalled = false;
      useCase.emitUpdate = (
          {newState,
          aviatorName,
          aviatorArgs,
          groupsToRebuild,
          bool skipIfSame = false}) {
        updateCalled = true;
      };

      // Track emitted statuses
      final emittedStatuses = <StreamStatus>[];
      final subscription = bloc.stream.listen(emittedStatuses.add);

      // Create custom use case with failure
      final failureUseCase = CustomFailureUseCase();
      failureUseCase.bloc = bloc;

      // Set up all emitter functions
      failureUseCase.emitFailure = (
          {newState,
          aviatorName,
          aviatorArgs,
          groupsToRebuild,
          Object? error,
          StackTrace? errorStackTrace}) {
        bloc.emit(StreamStatus.failure(
          newState as TestState? ?? bloc.state,
          bloc.state,
          TestEvent(groups: groupsToRebuild),
          error: error,
          errorStackTrace: errorStackTrace,
        ));
      };
      failureUseCase.emitUpdate = useCase.emitUpdate;
      failureUseCase.emitWaiting = useCase.emitWaiting;
      failureUseCase.emitCancel = useCase.emitCancel;
      failureUseCase.emitEvent = useCase.emitEvent;

      // Execute use case with failure
      await failureUseCase.execute(TestEvent());

      // Verify failure status was emitted
      expect(emittedStatuses.length, 1);
      expect(emittedStatuses[0] is FailureStatus, true);
      expect(updateCalled, false); // emitUpdate not called

      // Clean up
      await subscription.cancel();
    });
  });

  group('Relay Use Case Tests', () {
    late TestBloc sourceBloc;
    late SecondTestBloc targetBloc;
    late RelayTestUseCase relayUseCase;

    setUp(() {
      sourceBloc = TestBloc(initialState: TestState(value: 0));
      targetBloc =
          SecondTestBloc(initialState: SecondTestState(status: 'Initial'));

      relayUseCase = RelayTestUseCase();
      relayUseCase.bloc = sourceBloc;
      relayUseCase.targetBloc = targetBloc;

      // Set up emitter functions
      relayUseCase.emitUpdate = (
          {newState,
          aviatorName,
          aviatorArgs,
          groupsToRebuild,
          bool skipIfSame = false}) {
        sourceBloc.emit(StreamStatus.updating(
          newState as TestState? ?? sourceBloc.state,
          sourceBloc.state,
          TestEvent(groups: groupsToRebuild),
        ));
      };

      relayUseCase.emitWaiting =
          ({newState, aviatorName, aviatorArgs, groupsToRebuild}) {
        sourceBloc.emit(StreamStatus.waiting(
          newState as TestState? ?? sourceBloc.state,
          sourceBloc.state,
          TestEvent(groups: groupsToRebuild),
        ));
      };

      relayUseCase.emitFailure = (
          {newState,
          aviatorName,
          aviatorArgs,
          groupsToRebuild,
          Object? error,
          StackTrace? errorStackTrace}) {
        sourceBloc.emit(StreamStatus.failure(
          newState as TestState? ?? sourceBloc.state,
          sourceBloc.state,
          TestEvent(groups: groupsToRebuild),
          error: error,
          errorStackTrace: errorStackTrace,
        ));
      };

      relayUseCase.emitCancel =
          ({newState, aviatorName, aviatorArgs, groupsToRebuild}) {
        sourceBloc.emit(StreamStatus.canceling(
          newState as TestState? ?? sourceBloc.state,
          sourceBloc.state,
          TestEvent(groups: groupsToRebuild),
        ));
      };

      relayUseCase.emitEvent = ({EventBase? event}) {
        if (event != null) {
          sourceBloc.send(event);
        }
      };
    });

    tearDown(() {
      sourceBloc.close();
      targetBloc.close();
    });

    test('Relay use case updates both source and target blocs', () async {
      // Execute relay use case
      await relayUseCase.execute(TestEvent());

      // Verify source bloc state updated
      expect(sourceBloc.state.value, 1);

      // Verify target bloc state updated
      expect(targetBloc.state.status, 'Updated from relay: 1');
    });
  });
}

// Custom use cases for testing specific emissions
class CustomWaitingUseCase extends BlocUseCase<TestBloc, TestEvent> {
  @override
  Future<void> execute(TestEvent event) async {
    emitWaiting(groupsToRebuild: {"test-group"});
  }
}

class CustomFailureUseCase extends BlocUseCase<TestBloc, TestEvent> {
  @override
  Future<void> execute(TestEvent event) async {
    emitFailure(groupsToRebuild: {"test-group"});
  }
}
