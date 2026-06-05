import 'package:juice/juice.dart';

import '../realtime_bloc.dart';
import '../realtime_events.dart';
import '../realtime_state.dart';

/// Handles [ConnectionEstablishedEvent] — connected; reset reconnect attempts.
class ConnectionEstablishedUseCase
    extends BlocUseCase<RealtimeBloc, ConnectionEstablishedEvent> {
  @override
  Future<void> execute(ConnectionEstablishedEvent event) async {
    emitUpdate(
      newState: bloc.state.copyWith(
        status: RealtimeStatus.connected,
        reconnectAttempts: 0,
        lastError: null,
      ),
      groupsToRebuild: {RealtimeGroups.status},
    );
  }
}
