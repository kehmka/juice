import 'package:juice/juice.dart';
import '../source_bloc.dart';
import '../source_events.dart';

class IncrementSourceUseCase
    extends BlocUseCase<SourceBloc, IncrementSourceEvent> {
  @override
  Future<void> execute(IncrementSourceEvent event) async {
    emitUpdate(
      newState: bloc.state.copyWith(
        counter: bloc.state.counter + 1,
        clearError: true,
      ),
      groupsToRebuild: {'source'},
    );
  }
}

class DecrementSourceUseCase
    extends BlocUseCase<SourceBloc, DecrementSourceEvent> {
  @override
  Future<void> execute(DecrementSourceEvent event) async {
    emitUpdate(
      newState: bloc.state.copyWith(
        counter: bloc.state.counter - 1,
        clearError: true,
      ),
      groupsToRebuild: {'source'},
    );
  }
}

class SimulateAsyncUseCase
    extends BlocUseCase<SourceBloc, SimulateAsyncEvent> {
  @override
  Future<void> execute(SimulateAsyncEvent event) async {
    // Emit waiting state - this will be picked up by StatusRelay
    emitWaiting(groupsToRebuild: {'source'});

    // Simulate async operation
    await Future.delayed(const Duration(seconds: 2));

    // Complete with incremented counter
    emitUpdate(
      newState: bloc.state.copyWith(
        counter: bloc.state.counter + 10,
        isProcessing: false,
        clearError: true,
      ),
      groupsToRebuild: {'source'},
    );
  }
}

class SimulateErrorUseCase
    extends BlocUseCase<SourceBloc, SimulateErrorEvent> {
  @override
  Future<void> execute(SimulateErrorEvent event) async {
    // Emit failure state - this will be picked up by StatusRelay
    emitFailure(
      newState: bloc.state.copyWith(
        errorMessage: 'Simulated error occurred!',
      ),
      groupsToRebuild: {'source'},
    );
  }
}

class ResetSourceUseCase extends BlocUseCase<SourceBloc, ResetSourceEvent> {
  @override
  Future<void> execute(ResetSourceEvent event) async {
    emitUpdate(
      newState: bloc.state.copyWith(
        counter: 0,
        isProcessing: false,
        clearError: true,
      ),
      groupsToRebuild: {'source'},
    );
  }
}
