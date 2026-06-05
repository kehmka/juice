import 'package:juice/juice.dart';

import '../realtime_bloc.dart';
import '../realtime_events.dart';
import '../realtime_state.dart';

/// Handles [DisconnectEvent] — user-initiated close; stop reconnecting.
class DisconnectUseCase extends BlocUseCase<RealtimeBloc, DisconnectEvent> {
  @override
  Future<void> execute(DisconnectEvent event) async {
    bloc.markManualClose();
    await bloc.teardownConnection();

    emitUpdate(
      newState: bloc.state.copyWith(
        status: RealtimeStatus.disconnected,
        reconnectAttempts: 0,
      ),
      groupsToRebuild: {RealtimeGroups.status},
    );
  }
}
