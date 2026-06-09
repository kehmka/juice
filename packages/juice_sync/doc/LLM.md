# juice_sync — AI reference

> Per-package AI card. Format mirrors every package's `doc/LLM.md`. For the
> framework mental model + universal gotchas, read the repo-root `AGENTS.md`
> first. For full design depth, see `SPEC.md` (this folder).

## Purpose

Offline **outbox / mutation queue**: durably persist writes, then flush them to a
backend when online — with partitioned-FIFO ordering, backoff retries, and
dead-lettering. At-least-once delivery.

- **Owns:** the durable queue of pending writes + their delivery state.
- **Does NOT own:** the transport (a seam), offline *reads*/caching
  (`juice_network`), or your optimistic local read model.

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
  store: StorageSyncStore(storageBloc),          // durable persistence (juice_storage)
  executor: (m) => myApi.replay(m),              // transport — see seam below
  onlineSignal: connectivityOnlineStream,        // Stream<bool>; false→true edge auto-flushes
  maxAttempts: 8,                                 // then dead-letter
));
```

## Seams (what you implement)

```dart
// Transport — replay one mutation. REQUIRED.
typedef MutationExecutor = Future<void> Function(Mutation m);
//  • return normally        → success
//  • throw PermanentSyncError → dead-letter (4xx / validation)
//  • throw anything else     → retryable (network/5xx/429) → backoff
//  • CONTRACT: send m.id as the idempotency key; server must dedupe (at-least-once).

// Persistence — REQUIRED. Default StorageSyncStore (durable) + InMemorySyncStore (tests).
abstract class SyncStore {
  Future<void> put(Mutation m);
  Future<void> delete(String id);
  Future<List<Mutation>> loadAll();   // MUST return seq-ascending
  Future<int> nextSeq();              // monotonic, persisted
  Future<void> dispose();
}
```

## API

```dart
Future<Mutation> enqueue(String type, Map<String,Object?> payload, {String? orderingKey});
void flush();
Future<void> retryFailed([String? id]);   // dead-letter → pending (tail)
void discard(String id);
```

`enqueue` returns once **durably** persisted; it **throws** if the write can't
persist or the payload isn't JSON-serializable (fail-loud — never reports an
un-persisted write as queued).

## State & rebuild groups

```dart
class SyncState {                 // status: loading | idle | syncing | error
  List<Mutation> pending; List<Mutation> failed;
  bool online; int processedCount; String? lastError;
  int get pendingCount; int get failedCount; bool get isSyncing; bool get hasFailures;
}
```

| Group | Emitted when |
|---|---|
| `SyncGroups.status` | status/online/counts changed (cheap, frequent) |
| `SyncGroups.queue` | pending membership changed |
| `SyncGroups.failed` | dead-letter set changed |
| `SyncGroups.mutation(id)` → `sync:mutation:<id>` | one mutation's transition |

## Canonical use

```dart
// Enqueue (durably) — auto-flushes if online.
await sync.enqueue('createTodo', {'title': 'Buy milk'});

// Adapter for the executor seam (Dio shown; FetchBloc / any client works):
Future<void> myExecutor(Mutation m) async {
  try {
    await dio.request('/api/${m.type}', data: m.payload,
        options: Options(method: 'POST', headers: {'Idempotency-Key': m.id}));
  } on DioException catch (e) {
    final c = e.response?.statusCode ?? 0;
    if (c >= 400 && c < 500 && c != 429) throw PermanentSyncError('rejected $c'); // dead-letter
    rethrow;                                                                       // retry
  }
}

// Per-mutation tile (selective rebuild):
class SyncTile extends StatelessJuiceWidget<SyncBloc> {
  SyncTile({required this.id}) : super(key: ValueKey(id), groups: {SyncGroups.mutation(id)});
  final String id;
  @override Widget onBuild(BuildContext c, StreamStatus s) { /* read from bloc.state.pending/failed */ }
}
```

## Package-specific invariants

- **Partitioned FIFO:** mutations sharing an `orderingKey` are strict in-order;
  different keys (or null = independent) proceed past a blocked partition.
- **Crash-safe at-least-once:** `inFlight` is persisted before send; the durable
  `delete` completes before the queue head advances; a recovered `inFlight` on
  next launch is re-sent (never auto-dead-lettered).
- **Single-owner flush** via an `_isFlushing` guard + a `_pendingFlushRequest`
  re-check — all triggers funnel through one `FlushRequestedEvent`. (See the
  framework concurrency modes in AGENTS.md §4; `EventConcurrency.droppable` could
  replace the flag, the re-check still handles work enqueued mid-flush.)
- **Online trigger is injected** (`onlineSignal`), not a `juice_connectivity`
  dependency. Adapt `ConnectivityBloc.state.isOnline` into the stream.
- Known 0.2 edge: `close()` during an in-flight flush — see ROADMAP "known
  edge-case items".
