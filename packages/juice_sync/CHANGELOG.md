# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.0] - 2026-09-15

### Changed — behaviour, not cleanup (ISSUES #22)
- Requires `juice: ^1.6.0`. Every `UseCaseBuilder` now declares an
  `EventConcurrency` mode (the package predated 1.5.0 and ran everything
  `concurrent`, which silently allowed same-type use cases to interleave
  across an `await`):
  - `InitializeSyncEvent` → `droppable` (a second init mid-load is ignored).
  - `EnqueueMutationEvent`, `RetryFailedEvent`, `DiscardMutationEvent`,
    `OnlineChangedEvent` → `sequential` (same-type events run one at a time,
    in order; a read before an `await` can no longer be written stale).
  - `FlushRequestedEvent` → `concurrent`, explicitly, WITH its hand-rolled
    single-owner guard kept: a trigger arriving mid-flush sets a re-run flag so
    the pass repeats and catches mutations enqueued after its snapshot. Neither
    `droppable` (would drop the trigger) nor `sequential` (one extra pass per
    trigger) reproduces that.
- Known, documented, deferred: modes are keyed by exact event type, so
  `RetryFailedEvent` and `DiscardMutationEvent` are each serialized against
  themselves, not each other — `retryFailed()` then `discard(id)` on the same
  id inside one store write can resurrect it. A bloc-owned mutation FIFO (the
  `juice_storage` / `juice_i18n` pattern) closes it and is deferred until a
  consumer needs it.

### Tests
- Gated-store coverage: overlapping initializations coalesce to one `loadAll`;
  overlapping retries serialize (the second `put` waits for the first);
  a mutation enqueued mid-flush is sent by the same flush (the re-run flag).

## [0.1.2] - 2026-06-16

### Changed
- Allow `juice_storage` 2.0.0 (Hive CE migration). Test now uses `hive_ce`. No
  API change.

## [0.1.1] - 2026-06-16

### Fixed

- **`StorageSyncStore` now opens its own Hive boxes** (outbox + the private meta
  box) before first use. Previously the app was expected to pre-open them via
  `StorageConfig.hiveBoxesToOpen`, but it *can't* — the meta box name is
  internal — so `loadAll` failed with `boxNotOpen` at startup, putting `SyncBloc`
  into `SyncStatus.error`. Open is idempotent, so the store self-heals. Surfaced
  by the Glean dogfood.

### Changed

- `StorageSyncError.toString()` now includes its `cause`, so a wrapped storage
  failure is visible instead of opaque.

## [0.1.0] - 2026-05-28

### Added

- Initial release.
- **`SyncBloc`** — an offline outbox / mutation queue: durably persist writes,
  then flush them to a backend when online.
- **Durable persistence** — `SyncStore` seam; `StorageSyncStore` (juice_storage-
  backed, FIFO via a persisted `seq` counter) + `InMemorySyncStore` (tests).
- **`MutationExecutor`** — injected transport seam. `PermanentSyncError` ⇒
  dead-letter; any other throw ⇒ retryable.
- **Partitioned FIFO ordering** — mutations sharing an `orderingKey` are strict
  in-order; independent partitions proceed past a blocked one.
- **Exponential-backoff retries** with `maxAttempts` ⇒ dead-letter (a poison
  mutation can't wedge the queue).
- **Crash-safe at-least-once** — `inFlight` is persisted before send; a recovered
  `inFlight` is re-sent (relies on server idempotency on `mutation.id`).
- **Auto-flush** on a `false→true` edge of `onlineSignal`; optional
  `periodicRetry`.
- **Fail-loud** — `enqueue` throws if the write can't be persisted; `loadAll`
  failure ⇒ error status (never a silently-empty queue); non-JSON payloads
  rejected at `enqueue`.
- **API** — `enqueue`, `flush`, `retryFailed`, `discard`.
- **Rebuild groups** — `sync:status`, `sync:queue`, `sync:failed`,
  `sync:mutation:<id>`.

### Not yet included

- Backoff jitter, lean-state for very large queues, and offline-read pausing
  (`juice_network_connectivity`) — planned post-0.1.
