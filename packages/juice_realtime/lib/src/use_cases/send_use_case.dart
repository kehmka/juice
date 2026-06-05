import 'package:juice/juice.dart';

import '../realtime_bloc.dart';
import '../realtime_events.dart';
import '../realtime_state.dart';

/// Handles [SendEvent] — send over the live connection.
///
/// Fails loudly if not connected (never a silent drop).
class SendUseCase extends BlocUseCase<RealtimeBloc, SendEvent> {
  @override
  Future<void> execute(SendEvent event) async {
    if (!bloc.hasConnection || bloc.state.status != RealtimeStatus.connected) {
      emitFailure(
        newState: bloc.state.copyWith(lastError: 'Cannot send: not connected'),
        groupsToRebuild: {RealtimeGroups.status},
        error: StateError('RealtimeBloc.send() while not connected'),
      );
      return;
    }

    try {
      await bloc.sendData(event.data);
    } catch (e) {
      emitFailure(
        newState: bloc.state.copyWith(lastError: e.toString()),
        groupsToRebuild: {RealtimeGroups.status},
        error: e,
      );
    }
  }
}
