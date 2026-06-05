import 'package:juice/juice.dart';

import '../sync_bloc.dart';
import '../sync_events.dart';
import '../sync_state.dart';

/// Handles [EnqueueMutationEvent] — fold an already-persisted mutation into
/// pending and trigger a flush if online. (Durable persistence happened in
/// `SyncBloc.enqueue` so a put failure already surfaced to the caller.)
class EnqueueMutationUseCase extends BlocUseCase<SyncBloc, EnqueueMutationEvent> {
  @override
  Future<void> execute(EnqueueMutationEvent event) async {
    emitUpdate(
      newState: bloc.state.copyWith(pending: [...bloc.state.pending, event.mutation]),
      groupsToRebuild: {
        SyncGroups.queue,
        SyncGroups.status,
        SyncGroups.mutation(event.mutation.id),
      },
    );

    if (bloc.state.online) {
      bloc.send(FlushRequestedEvent());
    }
  }
}
