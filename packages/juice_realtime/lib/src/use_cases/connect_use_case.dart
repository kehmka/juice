import 'package:juice/juice.dart';

import '../realtime_bloc.dart';
import '../realtime_events.dart';
import '../realtime_state.dart';

/// Handles [ConnectEvent] — a fresh (user-initiated) connect. Resets attempts.
class ConnectUseCase extends BlocUseCase<RealtimeBloc, ConnectEvent> {
  @override
  Future<void> execute(ConnectEvent event) async {
    if (bloc.isConnecting) return; // a connect is already in flight
    final connectionEpoch = bloc.beginConnecting(userInitiated: true);
    await bloc.teardownConnection();

    if (!bloc.isCurrentConnectionEpoch(connectionEpoch)) return;

    emitUpdate(
      newState: bloc.state.copyWith(
        status: RealtimeStatus.connecting,
        reconnectAttempts: 0,
        lastError: null,
      ),
      groupsToRebuild: {RealtimeGroups.status},
    );

    await bloc.openConnection(connectionEpoch);
  }
}
