import 'package:juice/juice.dart';

import '../mutation.dart';
import '../sync_bloc.dart';
import '../sync_errors.dart';
import '../sync_events.dart';
import '../sync_state.dart';

/// Handles [RetryFailedEvent] — move dead-lettered mutation(s) back to pending
/// (at the tail, with attempts reset) and re-flush.
///
/// Re-inserting at the tail is a deliberate, documented reordering: a dead-letter
/// lost its ordering slot, so it goes behind newer writes.
class RetryFailedUseCase extends BlocUseCase<SyncBloc, RetryFailedEvent> {
  @override
  Future<void> execute(RetryFailedEvent event) async {
    final toRetry = event.id == null
        ? [...bloc.state.failed]
        : bloc.state.failed.where((m) => m.id == event.id).toList();
    if (toRetry.isEmpty) return;

    final revived = <Mutation>[];
    for (final m in toRetry) {
      final r = m.copyWith(status: MutationStatus.pending, attempts: 0, lastError: null);
      try {
        await bloc.store.put(r);
      } catch (e) {
        emitFailure(
          newState: bloc.state.copyWith(
            lastError: StorageSyncError('put failed', cause: e).toString(),
          ),
          groupsToRebuild: {SyncGroups.status},
          error: e,
        );
        return;
      }
      revived.add(r);
    }

    final revivedIds = revived.map((m) => m.id).toSet();
    emitUpdate(
      newState: bloc.state.copyWith(
        failed: bloc.state.failed.where((m) => !revivedIds.contains(m.id)).toList(),
        pending: [...bloc.state.pending, ...revived],
      ),
      groupsToRebuild: {
        SyncGroups.failed,
        SyncGroups.queue,
        SyncGroups.status,
        ...revivedIds.map(SyncGroups.mutation),
      },
    );

    if (bloc.state.online) bloc.send(FlushRequestedEvent());
  }
}
