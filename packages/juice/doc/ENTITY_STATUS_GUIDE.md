# Per-Item Async State: `EntityStatus` — A Guide

> A practical, example-first walkthrough of `EntityStatuses<K>` and
> `BlocUseCase.guardEntity`. For the formal contract, see
> [`ENTITY_STATUS_SPEC.md`](ENTITY_STATUS_SPEC.md).

---

## The problem in one sentence

`StreamStatus` tells you *the bloc* is waiting/failing. It can't tell you that
**row 7 of a list** is waiting while the others are fine.

That's the whole feature. If you've ever wanted a spinner on *one* list item — a
file uploading, a row being deleted, a message resending — and found yourself
adding a `Set<String> _busyIds` to your state, this is the framework's answer.

---

## Why `StreamStatus` isn't enough

`StreamStatus` is **one transient pulse for the whole bloc**:

```dart
emitWaiting();  // "the bloc is loading"  ← exactly one current status
emitUpdate();   // "the bloc is up to date"
emitFailure();  // "the bloc failed"
```

That's perfect for "load the screen" or "submit the form." It falls apart when a
collection has **many items, each with its own independent async life**:

- A photo list where each photo uploads on its own.
- A search-results list where each row can be re-fetched.
- An inbox where each message can be deleted or retried.

Here, "which items are in flight" is not a momentary pulse — it's **persistent,
queryable state**. So it belongs in your `BlocState`, and the framework's job is
to make that state *ergonomic and safe*, not to cram N workflows into one status.

### The hand-rolled version (and why it hurts)

```dart
// ❌ The thing everyone writes
class UploadsState extends BlocState {
  final List<FileItem> files;
  final Set<String> uploadingIds;   // waiting-only
  // ...no place for "this one FAILED, here's the error, offer retry"
}
```

Two problems bite:

1. **No failure surface.** A `Set` says "busy," never "failed with this error —
   retry?". So per-row errors get swallowed or flattened into a screen-wide banner.
2. **The stuck-spinner footgun.** You add an id to the set, `await`, and remove
   it — until the await *throws* and your `finally` is missing. Now the row spins
   forever.

---

## The mental model

`EntityStatus` is **`StreamStatus`, per item**. Same vocabulary
(idle / waiting / failure), one per entity key, living in your state:

| | `StreamStatus` | `EntityStatus` |
|---|---|---|
| grain | the whole bloc | one entity (by key) |
| how many | exactly one "current" | many, concurrent |
| lives in | the stream (transient) | `BlocState` (persistent) |
| you set it with | `emitWaiting/Update/Failure` | `guardEntity` / map mutators |
| you read it with | `onBuild`'s `status` arg | `state.field.statusOf(key)` |

Two pieces:

- **`EntityStatuses<K>`** — an immutable `key → status` map you put in your state.
- **`guardEntity`** — a `BlocUseCase` helper that runs your async work and moves
  one entity through `waiting → idle` (or `failure`), **cleanup guaranteed**.

---

## Worked example: a list of uploads

A list of files; each uploads independently, shows its own spinner, and on
failure shows an inline **Retry**. Copy-pasteable end to end.

### 1. State — hold an `EntityStatuses` keyed by item id

```dart
class UploadsState extends BlocState {
  final List<FileItem> files;
  final EntityStatuses<String> uploads; // keyed by file id

  const UploadsState({
    this.files = const [],
    this.uploads = const EntityStatuses<String>(),
  });

  UploadsState copyWith({
    List<FileItem>? files,
    EntityStatuses<String>? uploads,
  }) =>
      UploadsState(
        files: files ?? this.files,
        uploads: uploads ?? this.uploads,
      );
}
```

> `EntityStatuses` is immutable and has value equality, so it diffs cleanly for
> rebuilds. Idle == *absent from the map*, so the map only ever holds the items
> actually in flight — its size tracks work, not list length.

### 2. Use case — wrap the work in `guardEntity`

```dart
class UploadFileEvent extends EventBase {
  final String id;
  UploadFileEvent(this.id);
}

class UploadFileUseCase extends BlocUseCase<UploadsBloc, UploadFileEvent> {
  @override
  Future<void> execute(UploadFileEvent event) => guardEntity<String, void>(
        event.id,
        // locate the EntityStatuses in state, and write a new state with it:
        read: (b) => b.state.uploads,
        write: (s) => bloc.state.copyWith(uploads: s),
        groupsToRebuild: {'uploads'},
        // the risky work — may take time, may throw:
        action: () async {
          final file = bloc.state.files.firstWhere((f) => f.id == event.id);
          await bloc.uploadService.upload(file); // throws on network error
        },
      );
}
```

What `guardEntity` does, step by step:

1. `emitUpdate` with `uploads.waiting(id)` → the row shows a spinner.
2. `await action()`.
3. on success → `emitUpdate` with `uploads.idle(id)` → spinner gone.
4. on throw → `logError(...)` then `emitFailure` with `uploads.failure(id, error)`
   → the row shows the error. (Returns `null`; pass `rethrowOnError: true` to
   rethrow.)

The `try/finally` and the busy-set bookkeeping are gone, and **the failure now
has a home**.

### 3. Widget — `status.when(...)` per row

```dart
class UploadRow extends StatelessJuiceWidget<UploadsBloc> {
  UploadRow(this.id, {super.key}) : super(groups: const {'uploads'});
  final String id;

  @override
  Widget onBuild(BuildContext context, StreamStatus _) {
    final file = bloc.state.files.firstWhere((f) => f.id == id);
    final status = bloc.state.uploads.statusOf(id);

    return ListTile(
      title: Text(file.name),
      trailing: status.when(
        idle: () => IconButton(
          icon: const Icon(Icons.upload),
          onPressed: () => bloc.send(UploadFileEvent(id)),
        ),
        waiting: () => const SizedBox(
          width: 18, height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        failure: (error) => TextButton.icon(
          icon: const Icon(Icons.refresh),
          label: const Text('Retry'),
          onPressed: () => bloc.send(UploadFileEvent(id)), // same event retries
        ),
      ),
    );
  }
}
```

That's the entire feature: independent per-row spinners, a real per-row failure
state, one-tap retry, and no manual `setState` or busy-set anywhere.

---

## Per-item rebuilds (optional, for big lists)

By default a status change emits the list's group (`'uploads'`) and the whole
list rebuilds — fine for short lists with `const`/`RepaintBoundary` children.

For a large list where you want **only the changed row** to repaint, emit a
**keyed group** (the same trick the framework uses internally with
`ScopeGroups.byId`). Bind each row to its own key and have `guardEntity` emit it:

```dart
// row binds the collection group AND its own key:
UploadRow(this.id, {super.key})
    : super(groups: {'uploads', 'uploads:$id'});

// use case emits the keyed group too:
guardEntity<String, void>(
  event.id,
  read: (b) => b.state.uploads,
  write: (s) => bloc.state.copyWith(uploads: s),
  groupsToRebuild: {'uploads', 'uploads:${event.id}'},
  action: ...,
);
```

Now an uploading row never rebuilds its siblings — per-item reactivity with
**zero per-item blocs**.

---

## Patterns & FAQ

**Q: My bloc tracks two different per-item things (uploads *and* deletes).**
Hold two `EntityStatuses` fields and point each `guardEntity` at the right one
via `read`/`write`. The closures are why the helper isn't tied to one state shape:

```dart
// delete uses its own map
guardEntity<String, void>(id,
  read: (b) => b.state.deletes,
  write: (s) => bloc.state.copyWith(deletes: s),
  action: () => bloc.repo.delete(id));
```

**Q: My `action` itself emits (e.g. it replaces the item's data on success).**
That composes — `read`/`write` re-read the *current* state on each step, so your
action's own `emitUpdate` is preserved, and `guardEntity` clears the busy flag on
top of the newer state.

**Q: How do I show a list-level "something is uploading" indicator?**
`state.uploads.anyWaiting` (also `waitingKeys`, `failedKeys`).

**Q: Do I ever read it without `.when`?**
Yes: `isWaiting(key)` / `isFailure(key)` / `statusOf(key)` for quick checks (e.g.
dim a row while it works). Use `maybeWhen(..., orElse: ...)` for partial matches.

**Q: What's "idle"?**
The absence of an entry. `idle(key)` removes the key; an unknown key reads as
`EntityIdle()`. This keeps the map small and makes "never touched" and "finished"
both read as idle (which is what you want).

---

## Pitfalls

- **Don't reach for a bloc-per-item.** A leased bloc per list row gives each row a
  real `StreamStatus`, but N blocs for N scrolling rows is real lifecycle + render
  cost. `EntityStatuses` + keyed groups get the same result far cheaper.
- **Don't extend `StreamStatus` to be keyed.** It would muddy the clean
  "one bloc, one current transition" model every widget binding relies on. Keep
  `StreamStatus` bloc-grained; per-item status is *state*.
- **Don't hand-roll the busy set anymore.** `guardEntity` exists specifically so
  you never write the leak-prone set-add / try-finally / set-remove dance.

---

## API at a glance

```dart
// Value types
sealed class EntityStatus { bool get isIdle / isWaiting / isFailure; }
class EntityIdle / EntityWaiting / EntityFailure(Object error)
extension on EntityStatus { when({idle, waiting, failure}); maybeWhen(...); }

class EntityStatuses<K> {
  EntityStatus statusOf(K key);          // EntityIdle() if untracked
  bool isWaiting(K) / isFailure(K);
  bool get anyWaiting;
  Iterable<K> get waitingKeys / failedKeys;
  EntityStatuses<K> waiting(K) / failure(K, Object) / idle(K) / clear();
}

// Use-case helper (on BlocUseCase)
Future<T?> guardEntity<K, T>(K key, {
  required EntityStatuses<K> Function(TBloc) read,
  required BlocState Function(EntityStatuses<K>) write,
  required Future<T> Function() action,
  Set<String>? groupsToRebuild,
  bool rethrowOnError = false,
});
```

All exported from `package:juice/juice.dart`. Full contract + design rationale:
[`ENTITY_STATUS_SPEC.md`](ENTITY_STATUS_SPEC.md).
