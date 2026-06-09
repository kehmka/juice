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
    bloc.beginConnecting();

    await bloc.teardownConnection();

    emitUpdate(
      newState: bloc.state.copyWith(status: RealtimeStatus.connecting),
      groupsToRebuild: {RealtimeGroups.status},
    );

    await bloc.openConnection();
  }
}
