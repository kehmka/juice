import 'dart:convert';
import 'dart:math' as math;

import 'package:juice/juice.dart';

import 'mutation.dart';
import 'sync_config.dart';
import 'sync_events.dart';
import 'sync_executor.dart';
import 'sync_state.dart';
import 'sync_store.dart';
import 'use_cases/discard_mutation_use_case.dart';
import 'use_cases/enqueue_mutation_use_case.dart';
import 'use_cases/flush_use_case.dart';
import 'use_cases/initialize_sync_use_case.dart';
import 'use_cases/online_changed_use_case.dart';
import 'use_cases/retry_failed_use_case.dart';

/// An offline outbox / mutation queue: durably persist writes, then flush them
/// to a backend when online — with partitioned FIFO ordering, exponential-backoff
/// retries, and dead-lettering.
///
/// Delivery is **at-least-once**: the [MutationExecutor] adapter must send
/// `mutation.id` as an idempotency key and the server must dedupe on it.
///
/// ```dart
/// final sync = SyncBloc.withConfig(SyncConfig(
///   store: StorageSyncStore(storageBloc),
///   executor: (m) => api.replay(m),
///   onlineSignal: connectivity.onlineStream,
/// ));
/// await sync.enqueue('createTodo', {'title': 'Buy milk'});
/// ```
class SyncBloc extends JuiceBloc<SyncState> {
  late SyncConfig _config;

  bool _isFlushing = false;
  bool _pendingFlushRequest = false;
  bool _closed = false;

  /// Per-partition earliest-retry time (a partition in backoff is skipped).
  final Map<String, DateTime> _partitionRetryAt = {};

  Timer? _backoffTimer;
  Timer? _periodicTimer;
  StreamSubscription<bool>? _onlineSub;

  SyncBloc()
      : super(
          SyncState.initial,
          [
            () => UseCaseBuilder(
                typeOfEvent: InitializeSyncEvent,
                useCaseGenerator: () => InitializeSyncUseCase()),
            () => UseCaseBuilder(
                typeOfEvent: EnqueueMutationEvent,
                useCaseGenerator: () => EnqueueMutationUseCase()),
            () => UseCaseBuilder(
                typeOfEvent: FlushRequestedEvent,
                useCaseGenerator: () => FlushUseCase()),
            () => UseCaseBuilder(
                typeOfEvent: RetryFailedEvent,
                useCaseGenerator: () => RetryFailedUseCase()),
            () => UseCaseBuilder(
                typeOfEvent: DiscardMutationEvent,
                useCaseGenerator: () => DiscardMutationUseCase()),
            () => UseCaseBuilder(
                typeOfEvent: OnlineChangedEvent,
                useCaseGenerator: () => OnlineChangedUseCase()),
          ],
        );

  /// Create and initialize in one step.
  factory SyncBloc.withConfig(SyncConfig config) {
    final bloc = SyncBloc();
    bloc.send(InitializeSyncEvent(config: config));
    return bloc;
  }

  // === Config (used by use cases) ===

  void configure(SyncConfig config) => _config = config;
  SyncConfig get config => _config;
  SyncStore get store => _config.store;
  MutationExecutor get executor => _config.executor;
  int get maxAttempts => _config.maxAttempts;
  bool get isClosing => _closed;

  /// Subscribe to the online signal (deduped edges → [OnlineChangedEvent]).
  void startOnlineListening() {
    final signal = _config.onlineSignal;
    if (signal != null) {
      _onlineSub = signal.listen((v) {
        if (!isClosed) send(OnlineChangedEvent(v));
      });
    }
    final period = _config.periodicRetry;
    if (period != null) {
      _periodicTimer = Timer.periodic(period, (_) {
        if (!isClosed) send(FlushRequestedEvent());
      });
    }
  }

  // === Flush guards (single-owner loop) ===

  bool get isFlushing => _isFlushing;
  void beginFlush() => _isFlushing = true;
  void endFlush() => _isFlushing = false;

  /// Called when a trigger arrives mid-flush: re-run after the current pass.
  void requestFlushAgain() => _pendingFlushRequest = true;
  bool consumeFlushAgain() {
    final v = _pendingFlushRequest;
    _pendingFlushRequest = false;
    return v;
  }

  // === Partition backoff ===

  bool isPartitionBlocked(String partition, DateTime now) {
    final at = _partitionRetryAt[partition];
    return at != null && at.isAfter(now);
  }

  void blockPartition(String partition, DateTime until) =>
      _partitionRetryAt[partition] = until;
  void clearPartition(String partition) => _partitionRetryAt.remove(partition);

  Duration backoffFor(int attempts) {
    final base = _config.initialBackoff * math.pow(2, attempts - 1).toDouble();
    return base > _config.maxBackoff ? _config.maxBackoff : base;
  }

  /// Schedule a single timer for the soonest blocked partition.
  void scheduleBackoffTimer() {
    _backoffTimer?.cancel();
    _backoffTimer = null;
    if (_partitionRetryAt.isEmpty) return;
    final now = DateTime.now();
    DateTime? soonest;
    for (final at in _partitionRetryAt.values) {
      if (at.isAfter(now) && (soonest == null || at.isBefore(soonest))) {
        soonest = at;
      }
    }
    if (soonest == null) return;
    final delay = soonest.difference(now);
    _backoffTimer = Timer(delay.isNegative ? Duration.zero : delay, () {
      if (!isClosed) send(FlushRequestedEvent());
    });
  }

  // === Public API ===

  /// Durably enqueue a mutation. Completes once persisted; throws if the write
  /// can't be persisted (fail-loud — never reports an un-persisted write as
  /// queued) or if [payload] isn't JSON-serializable.
  Future<Mutation> enqueue(
    String type,
    Map<String, Object?> payload, {
    String? orderingKey,
  }) async {
    // Validate serializability now, not at flush time.
    try {
      jsonEncode(payload);
    } catch (e) {
      throw ArgumentError('Mutation payload is not JSON-serializable: $e');
    }

    final seq = await store.nextSeq();
    final mutation = Mutation(
      id: 'm_${seq}_${type.hashCode.toUnsigned(20).toRadixString(36)}',
      seq: seq,
      type: type,
      payload: payload,
      orderingKey: orderingKey,
      createdAt: DateTime.now(),
    );

    await store.put(mutation); // throws on failure → propagates to caller
    send(EnqueueMutationEvent(mutation));
    return mutation;
  }

  void flush() => send(FlushRequestedEvent());
  void retryFailed([String? id]) => send(RetryFailedEvent(id));
  void discard(String id) => send(DiscardMutationEvent(id));

  @override
  Future<void> close() async {
    _closed = true;
    _backoffTimer?.cancel();
    _periodicTimer?.cancel();
    await _onlineSub?.cancel();
    try {
      await _config.store.dispose();
    } catch (_) {
      // Config may never have been applied; ignore.
    }
    await super.close();
  }
}
