import 'package:juice/juice.dart';

import '../sync_bloc.dart';
import '../sync_errors.dart';
import '../sync_events.dart';
import '../sync_state.dart';

/// Handles [DiscardMutationEvent] — permanently remove a mutation (pending or
/// failed). Durable delete completes before the state update.
class DiscardMutationUseCase extends BlocUseCase<SyncBloc, DiscardMutationEvent> {
  @override
  Future<void> execute(DiscardMutationEvent event) async {
    final id = event.id;
    final inPending = bloc.state.pending.any((m) => m.id == id);
    final inFailed = bloc.state.failed.any((m) => m.id == id);
    if (!inPending && !inFailed) return;

    try {
      await bloc.store.delete(id);
    } catch (e) {
      emitFailure(
        newState: bloc.state.copyWith(
          lastError: StorageSyncError('delete failed', cause: e).toString(),
        ),
        groupsToRebuild: {SyncGroups.status},
        error: e,
      );
      return;
    }

    bloc.clearPartition(id); // in case it was a blocked independent partition

    emitUpdate(
      newState: bloc.state.copyWith(
        pending: bloc.state.pending.where((m) => m.id != id).toList(),
        failed: bloc.state.failed.where((m) => m.id != id).toList(),
      ),
      groupsToRebuild: {
        SyncGroups.queue,
        SyncGroups.failed,
        SyncGroups.status,
        SyncGroups.mutation(id),
      },
    );
  }
}
