import 'package:juice/juice.dart';

import '../mutation.dart';
import '../sync_bloc.dart';
import '../sync_errors.dart';
import '../sync_events.dart';
import '../sync_state.dart';

List<Mutation> _replace(List<Mutation> list, Mutation m) =>
    [for (final x in list) if (x.id == m.id) m else x];

List<Mutation> _remove(List<Mutation> list, String id) =>
    [for (final x in list) if (x.id != id) x];

/// Handles [FlushRequestedEvent] — the guarded, partitioned-FIFO drain.
///
/// Single-owner loop: a trigger arriving mid-flush sets a re-run flag rather
/// than starting a second loop (closes the missed-wakeup race). Within a pass,
/// mutations sharing an `orderingKey` are strict FIFO; independent partitions
/// proceed past a blocked one.
class FlushUseCase extends BlocUseCase<SyncBloc, FlushRequestedEvent> {
  @override
  Future<void> execute(FlushRequestedEvent event) async {
    if (bloc.isFlushing) {
      bloc.requestFlushAgain();
      return;
    }
    bloc.beginFlush();
    try {
      var again = true;
      while (again) {
        final stop = await _pass();
        if (stop) break;
        again = bloc.consumeFlushAgain();
      }
    } finally {
      bloc.endFlush();
      bloc.scheduleBackoffTimer();
      if (bloc.state.status == SyncStatus.syncing) {
        emitUpdate(
          newState: bloc.state.copyWith(status: SyncStatus.idle),
          groupsToRebuild: {SyncGroups.status, SyncGroups.queue},
        );
      }
    }
  }

  /// One pass over the current pending snapshot. Returns true if a storage
  /// failure forced a hard stop.
  Future<bool> _pass() async {
    emitUpdate(
      newState: bloc.state.copyWith(status: SyncStatus.syncing),
      groupsToRebuild: {SyncGroups.status},
    );

    final snapshot = [...bloc.state.pending];
    final skip = <String>{};

    for (final m in snapshot) {
      if (bloc.isClosing) return false;
      // Skip if removed/changed since the snapshot.
      if (!bloc.state.pending.any((p) => p.id == m.id)) continue;

      final partition = m.partition;
      if (skip.contains(partition)) continue;
      if (bloc.isPartitionBlocked(partition, DateTime.now())) {
        skip.add(partition);
        continue;
      }

      final stop = await _processOne(m, partition, skip);
      if (stop) return true;
    }
    return false;
  }

  /// Returns true to hard-stop the whole flush (storage failure).
  Future<bool> _processOne(Mutation m, String partition, Set<String> skip) async {
    final inflight = m.copyWith(
      status: MutationStatus.inFlight,
      attempts: m.attempts + 1,
    );

    // Persist the in-flight marker before sending (crash-recoverable).
    if (await _persist(inflight)) return true; // storage failure → stop
    emitUpdate(
      newState: bloc.state.copyWith(pending: _replace(bloc.state.pending, inflight)),
      groupsToRebuild: {SyncGroups.mutation(m.id), SyncGroups.status},
    );

    try {
      await bloc.executor(inflight);
    } on PermanentSyncError catch (e) {
      await _deadLetter(inflight, e.message);
      bloc.clearPartition(partition);
      return false; // partition continues with its next item
    } catch (e) {
      if (inflight.attempts >= bloc.maxAttempts) {
        await _deadLetter(inflight, e.toString());
        bloc.clearPartition(partition);
      } else {
        final retry = inflight.copyWith(
          status: MutationStatus.pending,
          lastError: e.toString(),
        );
        if (await _persist(retry)) return true;
        emitUpdate(
          newState:
              bloc.state.copyWith(pending: _replace(bloc.state.pending, retry)),
          groupsToRebuild: {SyncGroups.mutation(m.id), SyncGroups.status},
        );
        bloc.blockPartition(
            partition, DateTime.now().add(bloc.backoffFor(retry.attempts)));
        skip.add(partition);
      }
      return false;
    }

    // Success — durable delete must complete before the head advances.
    try {
      await bloc.store.delete(m.id);
    } catch (e) {
      _emitStorageError('delete', e);
      return true;
    }
    bloc.clearPartition(partition);
    emitUpdate(
      newState: bloc.state.copyWith(
        pending: _remove(bloc.state.pending, m.id),
        processedCount: bloc.state.processedCount + 1,
      ),
      groupsToRebuild: {SyncGroups.mutation(m.id), SyncGroups.status, SyncGroups.queue},
    );
    return false;
  }

  /// Persist a mutation; on failure emit a storage error and signal stop.
  Future<bool> _persist(Mutation m) async {
    try {
      await bloc.store.put(m);
      return false;
    } catch (e) {
      _emitStorageError('put', e);
      return true;
    }
  }

  Future<void> _deadLetter(Mutation m, String error) async {
    final dead = m.copyWith(status: MutationStatus.failed, lastError: error);
    if (await _persist(dead)) return;
    emitUpdate(
      newState: bloc.state.copyWith(
        pending: _remove(bloc.state.pending, m.id),
        failed: [...bloc.state.failed, dead],
      ),
      groupsToRebuild: {SyncGroups.mutation(m.id), SyncGroups.failed, SyncGroups.status},
    );
  }

  void _emitStorageError(String op, Object e) {
    emitFailure(
      newState: bloc.state.copyWith(
        status: SyncStatus.idle,
        lastError: StorageSyncError('store.$op failed', cause: e).toString(),
      ),
      groupsToRebuild: {SyncGroups.status},
      error: e,
    );
  }
}
