# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
