/// Thrown by a [MutationExecutor] for a **non-retryable** failure (e.g. a 4xx
/// or a validation error). The mutation is dead-lettered immediately rather than
/// retried.
class PermanentSyncError implements Exception {
  final String message;
  final Object? cause;
  const PermanentSyncError(this.message, {this.cause});

  @override
  String toString() => 'PermanentSyncError: $message';
}

/// A failure of the durable [SyncStore] itself (disk full, corrupt box, a
/// counter that won't persist). Surfaced loudly — never swallowed — because a
/// storage failure means the outbox can't guarantee durability.
class StorageSyncError implements Exception {
  final String message;
  final Object? cause;
  const StorageSyncError(this.message, {this.cause});

  @override
  String toString() => 'StorageSyncError: $message';
}
