# juice_sync Specification

> **Status:** Implemented (shipping).
> **Package:** `juice_sync`
> **Primary Bloc:** `SyncBloc`

## Overview

An offline outbox / mutation queue: durably persist writes, then flush them to a
backend when online — partitioned FIFO ordering, exponential-backoff retries,
dead-lettering, crash-safe at-least-once delivery. The capstone of the family
(the offline-writes half).

## Domain boundary

- **Owns:** the durable queue of pending writes and their delivery state.
- **Does NOT own:** the transport (`MutationExecutor` seam), offline reads /
  caching (`juice_network`), or the optimistic local read model (consumer's
  repository).

## Dependencies

`juice` + `juice_storage` (substrate). **Not** `juice_network` /
`juice_connectivity` — transport is the `MutationExecutor` seam, the online
trigger is `SyncConfig.onlineSignal: Stream<bool>?` (consumer adapts
`ConnectivityBloc`).

## Seams

- `MutationExecutor = Future<void> Function(Mutation)` (required). Throw
  `PermanentSyncError` ⇒ dead-letter; any other throw ⇒ retryable. Contract: send
  `m.id` as the idempotency key (at-least-once).
- `SyncStore` (required): `put` / `delete` / `loadAll` (seq-ascending) /
  `nextSeq` (persisted monotonic) / `dispose`. Default `StorageSyncStore`
  (juice_storage; the only file referencing `StorageBloc`). `InMemorySyncStore`
  for tests/demos (not durable).

## Mutation

```dart
class Mutation {
  final String id;        // client id = idempotency key
  final int seq;          // monotonic, persisted — durable FIFO
  final String type;
  final Map<String, Object?> payload;
  final String? orderingKey;  // null => partition = id (independent)
  final DateTime createdAt;   // diagnostics only
  final int attempts;
  final String? lastError;
  final MutationStatus status; // pending | inFlight | failed
}
```

## Flush algorithm (partitioned FIFO)

All triggers (enqueue-if-online, online edge, backoff/periodic timer,
retryFailed, init) funnel through one `FlushRequestedEvent`. Same-type use cases
run concurrently by default, so an `_isFlushing` flag + a `_pendingFlushRequest`
trailing re-check make the drain single-owner (closes the missed-wakeup race).
(juice ≥ 1.5.0's `EventConcurrency.droppable` could replace the flag; the
re-check still matters for work enqueued mid-flush — a tracked follow-up.)

`effectivePartition(m) = orderingKey ?? id`. Each pass iterates pending (seq
order); per mutation: skip if its partition is in `skip` or under a backoff
`_partitionRetryAt`. Otherwise persist `inFlight` (attempts+1), run the executor:
- **success** → durable `delete` (before the head advances) → remove + `processedCount++` + clear partition.
- **`PermanentSyncError`** → dead-letter; partition continues.
- **retryable** → if `attempts >= maxAttempts` dead-letter; else persist, set
  `_partitionRetryAt[partition] = now + backoff`, add to `skip`.

A single `_backoffTimer` is scheduled for the soonest blocked partition.
`backoff = min(maxBackoff, initialBackoff·2^(attempts-1))` (deterministic; jitter
is post-0.1).

## Crash-safety (at-least-once)

`inFlight` is persisted before the executor; the durable `delete` completes
before the head advances. A crash after a successful send but before the delete
⇒ the mutation reloads on next launch and is re-sent — so delivery is
**at-least-once** and the server must dedupe on `id`. A recovered `inFlight` is
re-queued as pending (never auto-dead-lettered).

## Fail-loud

1. `enqueue` awaits `store.put`; a failure throws out of `enqueue` (never reports
   an un-persisted write as queued).
2. `loadAll` / `nextSeq` failure on init ⇒ `error` status, not an empty queue.
3. `store.delete` failure after a send ⇒ stop the loop with `StorageSyncError`.
4. `maxAttempts` ⇒ dead-letter (no infinite silent retry).
5. Non-JSON `payload` ⇒ throw at `enqueue`.
6. Delivery is named at-least-once — never claimed exactly-once.

## State & groups

`SyncState`: `pending`, `failed`, `status` (loading/idle/syncing/error),
`online`, `processedCount`, `lastError`. Groups: `sync:status` (cheap/frequent),
`sync:queue` (membership), `sync:failed`, `sync:mutation:<id>`.

Note: per-mutation groups target *discrete* events (enqueue/retry/discard)
cleanly; within a single flush *burst* the framework accumulates groups on the
one flush event, so touched mutations' widgets rebuild together — acceptable for
a burst.

## Events & use cases (6)

`InitializeSyncEvent` (load + recover + flush), `EnqueueMutationEvent`,
`FlushRequestedEvent` (the guarded drain), `RetryFailedEvent`,
`DiscardMutationEvent`, `OnlineChangedEvent`.

Public API: `Future<Mutation> enqueue(type, payload, {orderingKey})`, `flush()`,
`retryFailed([id])`, `discard(id)`.

## Testing

Headless with a controllable fake executor + `InMemorySyncStore`: enqueue/drain,
seq order, per-event selective refresh, permanent→dead-letter, retryable→backoff→
success, max-attempts→dead-letter, **partitioned ordering** (blocked key holds
siblings, independents proceed), **crash recovery** (seeded `inFlight` re-sent),
**fail-loud** (`put` throws out of `enqueue`; `loadAll` failure → error status),
online gating, retry/discard, close disposes store. 15 tests.

## Spec Version

| Version | Date | Status |
|---|---|---|
| 1.0 | 2026-05-28 | Implemented |
