import 'package:juice/juice.dart';

import 'mutation.dart';

/// Overall sync engine status.
enum SyncStatus {
  /// Loading the persisted queue (init).
  loading,

  /// Idle — nothing in flight.
  idle,

  /// A flush is in progress.
  syncing,

  /// Initialization failed (e.g. the store couldn't be read) — fail-loud, not
  /// a silently-empty queue.
  error,
}

/// Rebuild groups emitted by `SyncBloc`.
abstract final class SyncGroups {
  /// Cheap/frequent — status, online, counts, processedCount, lastError.
  static const status = 'sync:status';

  /// Pending queue membership changed (enqueue / drain / discard).
  static const queue = 'sync:queue';

  /// Dead-letter set changed.
  static const failed = 'sync:failed';

  /// One mutation's status changed. `mutation('x')` → `sync:mutation:x`.
  static String mutation(String id) => 'sync:mutation:$id';

  static const all = {status, queue, failed};
}

/// Immutable sync state.
class SyncState extends BlocState {
  /// Queued + retrying mutations, in `seq` order.
  final List<Mutation> pending;

  /// Dead-lettered mutations (permanent failure or attempts exhausted).
  final List<Mutation> failed;

  final SyncStatus status;

  /// Last value from `onlineSignal` (true if no signal configured).
  final bool online;

  /// Mutations successfully sent this session.
  final int processedCount;

  final String? lastError;

  const SyncState({
    this.pending = const [],
    this.failed = const [],
    this.status = SyncStatus.idle,
    this.online = true,
    this.processedCount = 0,
    this.lastError,
  });

  static const initial = SyncState();

  int get pendingCount => pending.length;
  int get failedCount => failed.length;
  bool get isSyncing => status == SyncStatus.syncing;
  bool get hasFailures => failed.isNotEmpty;
  bool get isIdle => pending.isEmpty && status == SyncStatus.idle;

  SyncState copyWith({
    List<Mutation>? pending,
    List<Mutation>? failed,
    SyncStatus? status,
    bool? online,
    int? processedCount,
    Object? lastError = _unset,
  }) {
    return SyncState(
      pending: pending ?? this.pending,
      failed: failed ?? this.failed,
      status: status ?? this.status,
      online: online ?? this.online,
      processedCount: processedCount ?? this.processedCount,
      lastError: identical(lastError, _unset) ? this.lastError : lastError as String?,
    );
  }

  @override
  String toString() =>
      'SyncState(${pending.length} pending, ${failed.length} failed, $status, online:$online)';
}

const Object _unset = Object();
