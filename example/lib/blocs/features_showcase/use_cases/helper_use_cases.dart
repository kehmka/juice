import 'package:juice/juice.dart';
import '../features_showcase_bloc.dart';
import '../features_showcase_events.dart';
import '../features_showcase_state.dart';

/// Clears any error state.
class ClearErrorUseCase
    extends BlocUseCase<FeaturesShowcaseBloc, ClearErrorEvent> {
  @override
  Future<void> execute(ClearErrorEvent event) async {
    emitUpdate(
      newState: bloc.state.copyWith(
        clearError: true,
        activityLog: [
          ...bloc.state.activityLog,
          'Error cleared',
        ],
      ),
      groupsToRebuild: {'error', 'activity'},
    );
  }
}

/// Resets all state to initial values.
class ResetUseCase extends BlocUseCase<FeaturesShowcaseBloc, ShowcaseResetEvent> {
  @override
  Future<void> execute(ShowcaseResetEvent event) async {
    emitUpdate(
      newState: const FeaturesShowcaseState().copyWith(
        activityLog: ['State reset to initial values'],
      ),
      groupsToRebuild: {'*'},
    );
  }
}

/// Updates the message with skipIfSame deduplication.
///
/// Demonstrates: skipIfSame prevents emission if message hasn't changed.
class UpdateMessageUseCase
    extends BlocUseCase<FeaturesShowcaseBloc, UpdateMessageEvent> {
  @override
  Future<void> execute(UpdateMessageEvent event) async {
    // With skipIfSame: true, if the message is the same, no emission occurs
    emitUpdate(
      newState: bloc.state.copyWith(
        message: event.message,
        activityLog: [
          ...bloc.state.activityLog,
          'Message update attempted: "${event.message}"',
        ],
      ),
      groupsToRebuild: {'message', 'activity'},
      skipIfSame: true,
    );
  }
}
