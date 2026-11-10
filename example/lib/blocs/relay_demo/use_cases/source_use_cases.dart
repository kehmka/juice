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

class SimulateAsyncUseCase extends BlocUseCase<SourceBloc, SimulateAsyncEvent> {
  @override
  Future<void> execute(SimulateAsyncEvent event) async {
    // "Busy" goes in the STATE: a reaction sees state, never the status
    // kind. The waiting status is still what this bloc's own widgets show.
    emitWaiting(
      newState: bloc.state.copyWith(isProcessing: true, clearError: true),
      groupsToRebuild: {'source'},
    );

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

class SimulateErrorUseCase extends BlocUseCase<SourceBloc, SimulateErrorEvent> {
  @override
  Future<void> execute(SimulateErrorEvent event) async {
    // The error goes in the state too, where a reaction can see it.
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
