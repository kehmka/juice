import 'package:juice/juice.dart';

import 'mutation.dart';
import 'sync_config.dart';

/// Base class for sync events.
abstract class SyncEvent extends EventBase {
  @override
  String toString() => runtimeType.toString();
}

/// Apply config, subscribe to the online signal, load the persisted queue.
class InitializeSyncEvent extends SyncEvent {
  final SyncConfig config;
  InitializeSyncEvent({required this.config});
}

/// Fold a (already-persisted) mutation into pending and trigger a flush.
class EnqueueMutationEvent extends SyncEvent {
  final Mutation mutation;
  EnqueueMutationEvent(this.mutation);
}

/// Request a flush. All triggers funnel through this single event.
class FlushRequestedEvent extends SyncEvent {}

/// Move a dead-lettered mutation (or all) back to pending and retry.
class RetryFailedEvent extends SyncEvent {
  final String? id;
  RetryFailedEvent(this.id);
}

/// Permanently remove a mutation (pending or failed).
class DiscardMutationEvent extends SyncEvent {
  final String id;
  DiscardMutationEvent(this.id);
}

/// Internal: the online signal changed.
class OnlineChangedEvent extends SyncEvent {
  final bool online;
  OnlineChangedEvent(this.online);
}
