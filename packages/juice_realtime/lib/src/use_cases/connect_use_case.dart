import 'package:juice/juice.dart';

import '../realtime_bloc.dart';
import '../realtime_events.dart';
import '../realtime_state.dart';

/// Handles [ConnectEvent] — a fresh (user-initiated) connect. Resets attempts.
class ConnectUseCase extends BlocUseCase<RealtimeBloc, ConnectEvent> {
  @override
  Future<void> execute(ConnectEvent event) async {
    if (bloc.isConnecting) return; // a connect is already in flight
    bloc.beginConnecting();
    await bloc.teardownConnection();

    emitUpdate(
      newState: bloc.state.copyWith(
        status: RealtimeStatus.connecting,
        reconnectAttempts: 0,
        lastError: null,
      ),
      groupsToRebuild: {RealtimeGroups.status},
    );

    await bloc.openConnection();
  }
}
