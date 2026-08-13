import 'package:juice/juice.dart';

import '../realtime_bloc.dart';
import '../realtime_events.dart';
import '../realtime_state.dart';

/// Handles [ReconnectEvent] — a scheduled reconnect fired. Preserves the
/// attempt count (unlike a user [ConnectEvent]).
class ReconnectUseCase extends BlocUseCase<RealtimeBloc, ReconnectEvent> {
  @override
  Future<void> execute(ReconnectEvent event) async {
    if (bloc.manualClose) return; // user disconnected meanwhile
    if (bloc.isConnecting) return; // a connect is already in flight
    final connectionEpoch = bloc.beginConnecting();

    await bloc.teardownConnection();

    if (!bloc.isCurrentConnectionEpoch(connectionEpoch)) return;

    emitUpdate(
      newState: bloc.state.copyWith(status: RealtimeStatus.connecting),
      groupsToRebuild: {RealtimeGroups.status},
    );

    await bloc.openConnection(connectionEpoch);
  }
}
