---
card_schema: "1.0"
package: juice_sync
version: 0.1.0
requires:
  juice: ">=1.4.0"
  juice_storage: ">=1.2.0"
updated: 2026-06-09
---

# juice_sync — AI card

> Offline outbox / mutation queue: durably persist writes, flush to a backend
> when online, with partitioned-FIFO ordering, backoff retries, and
> dead-lettering. Read repo `AGENTS.md` for the Juice mental model + gotchas.

## Purpose

**Owns:** the durable queue of pending writes + their delivery state.
**Does NOT own:** the transport (a seam), offline *reads*/caching
(`juice_network`), or your optimistic local read model.

## When to use

User actions must succeed offline and reach the server later (create/update/
delete that can't be lost). For read caching use `juice_network`; for live
streams use `juice_realtime`.

## Install

```yaml
dependencies:
  juice_sync: ^0.1.0
  juice_storage: ^1.2.0   # for the durable StorageSyncStore
```

## Construct

Both seams are **required** (no silent non-durable / no-transport defaults):

```dart
final sync = SyncBloc.withConfig(SyncConfig(
  store: StorageSyncStore(storageBloc),       // durable persistence
  executor: myExecutor,                        // transport (see Seams)
  onlineSignal: connectivityOnlineStream,      // Stream<bool>; false→true auto-flushes
  maxAttempts: 8,                              // then dead-letter
  initialBackoff: Duration(seconds: 1),
  maxBackoff: Duration(minutes: 5),
  periodicRetry: null,                         // optional Duration safety-net
));
```

## Seams

```dart
// Transport. REQUIRED.
typedef MutationExecutor = Future<void> Function(Mutation m);
//  return normally          → success
//  throw PermanentSyncError → dead-letter (4xx / validation)
//  throw anything else      → retryable (network/5xx/429) → backoff
//  CONTRACT: send m.id as the idempotency key; server dedupes (AT-LEAST-ONCE).

// Persistence. REQUIRED. Default StorageSyncStore (durable); InMemorySyncStore (tests only).
abstract class SyncStore {
  Future<void> put(Mutation m);
  Future<void> delete(String id);
  Future<List<Mutation>> loadAll();   // MUST be seq-ascending
  Future<int> nextSeq();              // monotonic, persisted
  Future<void> dispose();
}
```

## API

```dart
Future<Mutation> enqueue(String type, Map<String,Object?> payload, {String? orderingKey});
void flush();
Future<void> retryFailed([String? id]);   // dead-letter → pending (tail)
void discard(String id);                   // remove (pending or failed)
```

`enqueue` returns once **durably persisted**; it throws if persistence fails or
`payload` isn't JSON-serializable.

## Events

| Event | Effect |
|---|---|
| `InitializeSyncEvent(config)` | load queue, recover `inFlight`→pending, flush if online |
| `EnqueueMutationEvent(m)` | fold into pending, flush if online |
| `FlushRequestedEvent` | the guarded partitioned drain (all triggers funnel here) |
| `RetryFailedEvent(id?)` | revive dead-letter(s) → pending tail |
| `DiscardMutationEvent(id)` | durable delete |
| `OnlineChangedEvent(bool)` *internal* | from `onlineSignal`; false→true → flush |

## State

```dart
class SyncState {                 // status: loading | idle | syncing | error
  List<Mutation> pending; List<Mutation> failed;
  bool online; int processedCount; String? lastError;
  int get pendingCount; int get failedCount;
  bool get isSyncing; bool get hasFailures; bool get isIdle;
}
// Mutation: id, seq, type, payload, orderingKey, createdAt, attempts, lastError, status
// MutationStatus { pending, inFlight, failed }
```

## Rebuild groups

| Group | Emitted when |
|---|---|
| `SyncGroups.status` | status/online/counts changed (cheap, frequent) |
| `SyncGroups.queue` | pending membership changed |
| `SyncGroups.failed` | dead-letter set changed |
| `SyncGroups.mutation(id)` → `sync:mutation:<id>` | one mutation's transition |

## Concurrency

`FlushRequestedEvent` is registered `concurrent` (default) with a manual
single-owner guard: `_isFlushing` + a `_pendingFlushRequest` trailing re-check
(so work enqueued mid-flush is still drained). `EventConcurrency.droppable` is a
candidate to replace the flag, but the re-check would still be needed — tracked
in ROADMAP.

## Recipes

```dart
// 1. Executor adapter (Dio; FetchBloc / any client works the same way)
Future<void> myExecutor(Mutation m) async {
  try {
    await dio.request('/api/${m.type}', data: m.payload,
        options: Options(method: 'POST', headers: {'Idempotency-Key': m.id}));
  } on DioException catch (e) {
    final c = e.response?.statusCode ?? 0;
    if (c >= 400 && c < 500 && c != 429) throw PermanentSyncError('rejected $c');
    rethrow;  // retryable
  }
}

// 2. Wire the online signal from juice_connectivity (no direct dependency)
final online = connectivity.stream
    .map((_) => connectivity.state.isOnline).distinct();
// → SyncConfig(onlineSignal: online, ...)

// 3. Per-mutation tile (selective rebuild)
class SyncTile extends StatelessJuiceWidget<SyncBloc> {
  SyncTile({required this.id}) : super(key: ValueKey(id), groups: {SyncGroups.mutation(id)});
  final String id;
  @override Widget onBuild(BuildContext c, StreamStatus s) {
    final m = [...bloc.state.pending, ...bloc.state.failed].firstWhere((x) => x.id == id);
    return Text('${m.type}: ${m.status.name}');
  }
}
```

## Testing

Headless — fake the executor, use `InMemorySyncStore`:

```dart
class FakeExecutor {
  final sent = <Mutation>[];
  final permanent = <String>{};          // types that hard-fail
  Future<void> call(Mutation m) async {
    sent.add(m);
    if (permanent.contains(m.type)) throw const PermanentSyncError('no');
  }
}
final bloc = SyncBloc.withConfig(SyncConfig(store: InMemorySyncStore(), executor: ex.call));
await bloc.enqueue('createTodo', {'t': 1});
await settle();                          // Future.delayed(20ms)
expect(bloc.state.pending, isEmpty);
// Seed an inFlight Mutation into InMemorySyncStore([...]) to test crash recovery.
```

## Failure modes

- `enqueue` → throws `StorageSyncError` (persist failed) or `ArgumentError`
  (non-JSON payload). Surfaces to the caller; nothing is queued.
- Executor `PermanentSyncError` → mutation dead-lettered (in `state.failed`).
- Executor other throw → retried with backoff; after `maxAttempts` → dead-letter.
- `loadAll` failure on init → `status == error`, **not** an empty queue.
- Delivery is **at-least-once** (a crash between send and the durable delete
  replays) — never claim exactly-once.

## Anti-patterns

- ❌ `InMemorySyncStore` in production — it isn't durable; the outbox's whole
  point is surviving app kill. Use `StorageSyncStore`.
- ❌ An executor that doesn't send `m.id` as an idempotency key — at-least-once
  delivery will double-apply.
- ❌ Putting non-JSON-serializable objects in `payload`.
- ❌ Depending on `juice_connectivity`/`juice_network` from your sync wiring —
  pass them in via `onlineSignal` / `executor` seams.

## Integrates with

- **juice_storage** — `StorageSyncStore(storageBloc)` (durable default).
- **juice_connectivity** — adapt `ConnectivityBloc.state.isOnline` → `onlineSignal`.
- **juice_network / Dio / any client** — behind the `MutationExecutor`.

## Invariants

- **Partitioned FIFO:** same `orderingKey` is strict in-order; independent keys
  (null) proceed past a blocked partition.
- **Crash-safe:** `inFlight` persisted before send; durable `delete` before the
  head advances; recovered `inFlight` re-sent.
- **Durable order:** by persisted `seq` (hive keys are unordered).
- Known 0.2 edge: `close()` mid-flush — see ROADMAP "known edge-case items".

## See also

`SPEC.md` (design depth) · `README.md` (narrative) · repo `AGENTS.md` (framework).
