import 'package:juice/juice.dart';

import '../realtime_bloc.dart';
import '../realtime_events.dart';
import '../realtime_state.dart';

/// Handles [DisconnectEvent] — user-initiated close; stop reconnecting.
class DisconnectUseCase extends BlocUseCase<RealtimeBloc, DisconnectEvent> {
  @override
  Future<void> execute(DisconnectEvent event) async {
    final connectionEpoch = bloc.markManualClose();
    await bloc.teardownConnection();

    // A newer user connect supersedes this disconnect while teardown awaits.
    if (!bloc.isConnectionEpoch(connectionEpoch)) return;

    emitUpdate(
      newState: bloc.state.copyWith(
        status: RealtimeStatus.disconnected,
        reconnectAttempts: 0,
      ),
      groupsToRebuild: {RealtimeGroups.status},
    );
  }
}
