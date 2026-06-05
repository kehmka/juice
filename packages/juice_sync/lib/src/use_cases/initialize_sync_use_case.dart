import 'package:juice/juice.dart';

import '../mutation.dart';
import '../sync_bloc.dart';
import '../sync_errors.dart';
import '../sync_events.dart';
import '../sync_state.dart';

/// Handles [InitializeSyncEvent] — load the persisted queue (fail-loud),
/// recover any `inFlight` mutation as pending (re-send), then flush if online.
class InitializeSyncUseCase extends BlocUseCase<SyncBloc, InitializeSyncEvent> {
  @override
  Future<void> execute(InitializeSyncEvent event) async {
    bloc.configure(event.config);
    bloc.startOnlineListening();

    emitUpdate(
      newState: bloc.state.copyWith(status: SyncStatus.loading),
      groupsToRebuild: {SyncGroups.status},
    );

    final List<Mutation> loaded;
    try {
      loaded = await bloc.store.loadAll();
    } catch (e) {
      // Fail loud: do NOT start with a silently-empty queue.
      emitFailure(
        newState: bloc.state.copyWith(
          status: SyncStatus.error,
          lastError: StorageSyncError('loadAll failed', cause: e).toString(),
        ),
        groupsToRebuild: {SyncGroups.status},
        error: e,
      );
      return;
    }

    final pending = <Mutation>[];
    final failed = <Mutation>[];
    for (final m in loaded) {
      switch (m.status) {
        case MutationStatus.failed:
          failed.add(m);
        case MutationStatus.inFlight:
          // Was mid-send at crash — recover as pending and re-send (at-least-once).
          pending.add(m.copyWith(status: MutationStatus.pending));
        case MutationStatus.pending:
          pending.add(m);
      }
    }

    emitUpdate(
      newState: bloc.state.copyWith(
        pending: pending,
        failed: failed,
        status: SyncStatus.idle,
        lastError: null,
      ),
      groupsToRebuild: {SyncGroups.status, SyncGroups.queue, SyncGroups.failed},
    );

    if (bloc.state.online && pending.isNotEmpty) {
      bloc.send(FlushRequestedEvent());
    }
  }
}
