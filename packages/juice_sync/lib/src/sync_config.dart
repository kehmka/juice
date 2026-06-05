import 'sync_executor.dart';
import 'sync_store.dart';

/// Configures a `SyncBloc`.
class SyncConfig {
  /// Replays a mutation against the backend. **Required** — there's no universal
  /// transport.
  final MutationExecutor executor;

  /// Durable queue persistence. **Required** — a non-durable default would
  /// silently lose writes. Use `StorageSyncStore` for production.
  final SyncStore store;

  /// Online/offline signal. On a false→true edge the queue auto-flushes. Adapt
  /// `ConnectivityBloc.state.isOnline` into this stream. If null, flush only
  /// happens manually (or via `periodicRetry`).
  final Stream<bool>? onlineSignal;

  /// Max attempts before a retryable mutation is dead-lettered (no infinite
  /// retry).
  final int maxAttempts;

  /// Backoff before the first retry; doubles each attempt, capped at [maxBackoff].
  final Duration initialBackoff;
  final Duration maxBackoff;

  /// Optional periodic re-flush (a safety net when there's no online signal).
  final Duration? periodicRetry;

  const SyncConfig({
    required this.executor,
    required this.store,
    this.onlineSignal,
    this.maxAttempts = 8,
    this.initialBackoff = const Duration(seconds: 1),
    this.maxBackoff = const Duration(minutes: 5),
    this.periodicRetry,
  });
}
