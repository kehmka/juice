# juice_sync

An offline **outbox / mutation queue** as a [Juice](https://pub.dev/packages/juice)
bloc — durably persist writes, then flush them to a backend when online, with
ordering, retries, and dead-lettering.

[![pub package](https://img.shields.io/pub/v/juice_sync.svg)](https://pub.dev/packages/juice_sync)
[![License: MIT](https://img.shields.io/badge/license-MIT-purple.svg)](LICENSE)

## What it owns

The durable queue of pending writes and their delivery. It does **not** own the
transport (the `MutationExecutor` seam), offline *reads* / caching (that's
`juice_network`), or your optimistic local read model (your repository layer).

## Install

```yaml
dependencies:
  juice_sync: ^0.1.0
  juice_storage: ^1.2.0   # for the durable StorageSyncStore
```

## Use

```dart
final sync = SyncBloc.withConfig(SyncConfig(
  store: StorageSyncStore(storageBloc),        // durable (survives app kill)
  executor: (m) => api.replay(m),              // your transport
  onlineSignal: connectivityOnlineStream,      // adapt ConnectivityBloc.isOnline
));

// Returns once DURABLY queued; throws if it couldn't be persisted.
await sync.enqueue('createTodo', {'title': 'Buy milk'});
```

When offline, mutations queue durably; the queue auto-flushes on the next
`false→true` online edge.

## The executor seam (your backend)

`juice_sync` is transport-free — you wire ~10 lines:

```dart
Future<void> myExecutor(Mutation m) async {
  try {
    await dio.request(
      '/api/${m.type}',
      data: m.payload,
      options: Options(method: 'POST', headers: {'Idempotency-Key': m.id}),
    );
  } on DioException catch (e) {
    final code = e.response?.statusCode ?? 0;
    if (code >= 400 && code < 500 && code != 429) {
      throw PermanentSyncError('rejected: $code');   // → dead-letter
    }
    rethrow;                                          // → retry with backoff
  }
}
```

**Delivery is at-least-once.** The adapter must send `m.id` as an idempotency key
and the server must dedupe on it — a crash between a successful send and the
durable delete causes a replay.

## Ordering

Strict FIFO **per `orderingKey`**; independent keys (or null) don't block each
other:

```dart
await sync.enqueue('updateDoc', {...}, orderingKey: 'doc:42'); // ordered with…
await sync.enqueue('updateDoc', {...}, orderingKey: 'doc:42'); // …this one
await sync.enqueue('ping', {});                                // independent
```

A transient failure holds back only its own partition (bounded by
`maxAttempts`); a different doc keeps flowing.

## Retries & dead-letter

Retryable failures back off exponentially up to `maxAttempts` (default 8), then
move to the **dead-letter** set (`state.failed`). `retryFailed(id?)` revives
them; `discard(id)` drops one for good. A poison mutation can never wedge the
queue.

## Crash-safety

`inFlight` is persisted before the send and the durable delete completes before
the queue head advances. On the next launch the queue is reloaded (`seq`-ordered)
and any recovered `inFlight` is re-sent. If the store can't be read, the bloc
enters an **error** status — it never silently starts with an empty queue.

## State

| Field / getter | Meaning |
|---|---|
| `pending` | queued + retrying (seq order) |
| `failed` | dead-letter |
| `status` | loading / idle / syncing / error |
| `online` | last `onlineSignal` value |
| `processedCount` | sent this session |
| `pendingCount` / `failedCount` / `isSyncing` / `hasFailures` | derived |

Rebuild groups: `sync:status`, `sync:queue`, `sync:failed`,
`sync:mutation:<id>`. (Per-mutation groups target discrete events cleanly; within
a single flush *burst* the touched mutations' rebuilds coalesce.)

## License

MIT License — see [LICENSE](LICENSE).
