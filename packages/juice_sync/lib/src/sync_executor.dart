import 'mutation.dart';
import 'sync_errors.dart';

/// Replays one queued [Mutation] against a backend.
///
/// - Return normally on success.
/// - Throw [PermanentSyncError] for a non-retryable failure (4xx / validation):
///   the mutation is dead-lettered immediately.
/// - Throw anything else for a retryable failure (network / timeout / 5xx /
///   429): the mutation is retried with backoff, up to `maxAttempts`.
///
/// **Contract:** delivery is **at-least-once**. The adapter MUST send
/// `mutation.id` as the idempotency key, and the server MUST dedupe on it — a
/// crash between a successful send and the durable delete causes a replay.
///
/// Wire this to Dio / a `FetchBloc` / your API client in a few lines; `juice_sync`
/// stays transport-free.
typedef MutationExecutor = Future<void> Function(Mutation mutation);
