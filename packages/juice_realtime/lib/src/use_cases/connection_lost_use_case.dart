import 'package:juice/juice.dart';

import '../realtime_bloc.dart';
import '../realtime_events.dart';
import '../realtime_state.dart';

/// Handles [ConnectionLostEvent] — the connection dropped or failed to open.
///
/// If the user disconnected, stays disconnected. Otherwise schedules a backoff
/// reconnect — or gives up loudly once `maxReconnectAttempts` is exceeded.
class ConnectionLostUseCase
    extends BlocUseCase<RealtimeBloc, ConnectionLostEvent> {
  @override
  Future<void> execute(ConnectionLostEvent event) async {
    await bloc.teardownConnection();
    final error = event.error?.toString();

    if (bloc.manualClose) {
      emitUpdate(
        newState: bloc.state.copyWith(status: RealtimeStatus.disconnected),
        groupsToRebuild: {RealtimeGroups.status},
      );
      return;
    }

    final attempt = bloc.state.reconnectAttempts + 1;

    if (!bloc.canReconnect(attempt)) {
      // Give up — surface loudly rather than silently retrying forever.
      emitFailure(
        newState: bloc.state.copyWith(
          status: RealtimeStatus.disconnected,
          lastError: error ?? 'Connection lost; gave up after $attempt attempts',
        ),
        groupsToRebuild: {RealtimeGroups.status},
        error: event.error ?? StateError('realtime: reconnect attempts exhausted'),
      );
      return;
    }

    bloc.scheduleReconnect(attempt);
    emitUpdate(
      newState: bloc.state.copyWith(
        status: RealtimeStatus.reconnecting,
        reconnectAttempts: attempt,
        lastError: error,
      ),
      groupsToRebuild: {RealtimeGroups.status},
    );
  }
}
