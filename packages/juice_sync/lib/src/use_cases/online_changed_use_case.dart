import 'package:juice/juice.dart';

import '../sync_bloc.dart';
import '../sync_events.dart';
import '../sync_state.dart';

/// Handles [OnlineChangedEvent] — record online state; on a false→true edge,
/// flush the queue.
class OnlineChangedUseCase extends BlocUseCase<SyncBloc, OnlineChangedEvent> {
  @override
  Future<void> execute(OnlineChangedEvent event) async {
    final wasOnline = bloc.state.online;
    if (event.online == wasOnline) return; // dedupe

    emitUpdate(
      newState: bloc.state.copyWith(online: event.online),
      groupsToRebuild: {SyncGroups.status},
    );

    if (event.online && bloc.state.pending.isNotEmpty) {
      bloc.send(FlushRequestedEvent());
    }
  }
}
