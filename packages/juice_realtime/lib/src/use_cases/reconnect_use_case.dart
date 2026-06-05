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

    await bloc.teardownConnection();

    emitUpdate(
      newState: bloc.state.copyWith(status: RealtimeStatus.connecting),
      groupsToRebuild: {RealtimeGroups.status},
    );

    await bloc.openConnection();
  }
}
