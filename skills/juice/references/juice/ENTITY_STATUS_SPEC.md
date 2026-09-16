# EntityStatus Specification

> **Status:** Draft v0.1 (in-app trial in Glean; not yet published)
> **Package:** `juice` (core)
> **Purpose:** Per-item async status for collections — the item-grained companion to `StreamStatus`
> **New here?** Start with the example-first [`ENTITY_STATUS_GUIDE.md`](ENTITY_STATUS_GUIDE.md); this is the reference contract.

---

## Overview

`StreamStatus` models **one transient transition for the whole bloc** — "the bloc is, right now, `updating` / `waiting` / `failure` / `canceling`." That single-pulse model is what makes `status.when(...)` and group rebuilds clean.

But when a bloc owns a **collection whose items have independent, possibly concurrent async lifecycles** — re-read this row, upload that one, delete a third, retry a fourth — "the bloc is waiting" is the wrong grain. *Which* items are in flight is persistent, queryable **state**, not a single pulse.

`EntityStatus` adds that missing grain:

- **`EntityStatuses<K>`** — an immutable `key → status` map you embed in your `BlocState`.
- **`BlocUseCase.guardEntity`** — a use-case helper that drives one entity through `waiting → idle` (or `failure`) with cleanup guaranteed.
- **`EntityStatus.when`** — the same pattern-match ergonomics as `StreamStatus.when`, per item.

**Before:** a hand-rolled `String? rereadingId` (waiting-only, one item, no failure surface) and a manual `try/finally` to clear it.

**After:** `state.mediaStatus.statusOf(id).when(idle:…, waiting:…, failure:…)`, fed by a single `guardEntity(...)` call.

---

## The Problem

A bloc has a list. Each row can kick off its own async operation. Today you reach for one of:

```dart
String? rereadingId;            // waiting-only, ONE at a time, no failure
Set<String> busyIds;            // many waiting, still no failure, no error payload
Map<String, MyAdHocEnum> ...;   // bespoke vocabulary, re-invented per feature
```

Three things go wrong:

1. **No shared vocabulary.** Every feature models it differently, so none of the `StreamStatus`-style ergonomics (`.when`, exhaustive matching) apply at the item grain. They get re-implemented by hand, inconsistently.

2. **No per-item failure surface.** A single id or a `Set` can say "busy," but not "this row failed, here's the error, offer a retry." That UX has nowhere to live, so per-row errors get swallowed or flattened into a bloc-wide banner.

3. **The stuck-spinner footgun.** Hand-rolled busy state means: set busy → `await` → **forget the `finally`** → operation throws → the row spins forever. Bloc-wide `emitWaiting/emitFailure` are safe; per-item state is on you.

```dart
// The footgun
state = state.copyWith(rereadingId: id);   // busy
final text = await service.reread(media);  // throws...
state = state.copyWith(rereadingId: null); // ...never runs → stuck spinner
```

Crucially, this is **not** an argument to make `StreamStatus` per-key (see [Relationship to StreamStatus](#relationship-to-streamstatus)). The set of in-flight operations is genuinely persistent state; the framework's job is to make that state *ergonomic and safe*, not to fold N workflows into one status pulse.

---

## The Solution

A small, opt-in, dependency-free value type plus one use-case helper. No change to `StreamStatus`, no bloc-per-item, no framework coupling to your state shape.

```dart
// State: one field.
class GleaningState extends BlocState {
  final EntityStatuses<String> mediaStatus;   // keyed by media id
  // ...
}

// Use case: one call. waiting → run → idle, or failure on throw — guaranteed.
class RereadMediaUseCase extends BlocUseCase<GleaningBloc, RereadMediaEvent> {
  @override
  Future<void> execute(RereadMediaEvent e) => guardEntity<String, void>(
        e.mediaId,
        read: (b) => b.state.mediaStatus,
        write: (s) => bloc.state.copyWith(mediaStatus: s),
        groupsToRebuild: {GleaningGroups.review},
        action: () async { /* the risky work; may emit + may throw */ },
      );
}

// Widget: the same .when() ergonomics as StreamStatus, per row.
final status = bloc.state.mediaStatus.statusOf(m.id);
status.when(
  idle:    () => _Actions(...),
  waiting: () => const _Busy('re-reading…'),
  failure: (e) => _RetryRow(onRetry: () => bloc.rereadMedia(m.id, hint)),
);
```

---

## Core Types

### EntityStatus

A sealed type mirroring the `StreamStatus` vocabulary at the entity grain.

```dart
sealed class EntityStatus {
  const EntityStatus();
  bool get isIdle;     // this is EntityIdle
  bool get isWaiting;  // this is EntityWaiting
  bool get isFailure;  // this is EntityFailure
}

class EntityIdle    extends EntityStatus { const EntityIdle(); }
class EntityWaiting extends EntityStatus { const EntityWaiting(); }
class EntityFailure extends EntityStatus { final Object error; const EntityFailure(this.error); }
```

All three have value equality (so states diff correctly for `skipIfSame` / `onStateChange`). `EntityFailure` carries the `error` so the UI can show it and offer a retry.

**Pattern matching** (extension `EntityStatusX`):

```dart
T when<T>({
  required T Function() idle,
  required T Function() waiting,
  required T Function(Object error) failure,
});

T maybeWhen<T>({
  T Function()? idle,
  T Function()? waiting,
  T Function(Object error)? failure,
  required T Function() orElse,
});
```

### EntityStatuses\<K>

An immutable `Map<K, EntityStatus>`. **Idle is the absence of an entry** — only waiting/failed keys are ever stored, so the map stays small (proportional to in-flight work, not collection size). All mutators return a new instance.

```dart
class EntityStatuses<K> {
  const EntityStatuses([Map<K, EntityStatus> statuses = const {}]);

  // reads
  EntityStatus statusOf(K key);        // EntityIdle() if untracked
  bool isWaiting(K key);
  bool isFailure(K key);
  bool get anyWaiting;
  Iterable<K> get waitingKeys;
  Iterable<K> get failedKeys;
  bool get isEmpty;
  bool get isNotEmpty;
  int get length;

  // transitions (return a new instance)
  EntityStatuses<K> waiting(K key);
  EntityStatuses<K> failure(K key, Object error);
  EntityStatuses<K> idle(K key);       // removes the key; no-op (same instance) if absent
  EntityStatuses<K> clear();           // removes all
}
```

Value equality + `hashCode` are implemented (unordered over entries), so a status change produces a distinct state instance and an unchanged map compares equal.

---

## Driving status from use cases: `guardEntity`

A method on `BlocUseCase`. It brackets an async `action` with the entity's status lifecycle and **guarantees cleanup even on throw**.

```dart
Future<T?> guardEntity<K, T>(
  K key, {
  required EntityStatuses<K> Function(TBloc bloc) read,   // locate the map in state
  required BlocState Function(EntityStatuses<K> statuses) write, // new state w/ map
  required Future<T> Function() action,                   // the risky work
  Set<String>? groupsToRebuild,
  bool rethrowOnError = false,
});
```

Semantics:

1. `emitUpdate` with `read(bloc).waiting(key)` → the row shows busy.
2. `await action()`.
3. On success: `emitUpdate` with `read(bloc).idle(key)` → cleared.
4. On throw: `logError(...)` then `emitFailure` with `read(bloc).failure(key, error)` → the row shows the error. Returns `null` (or rethrows if `rethrowOnError`).

**`read`/`write` re-run each step**, so they always see the latest state — which is why the `action`'s *own* `emit`s compose. In Glean, the action replaces the reading text mid-flight; `guardEntity` then clears the busy flag on top of that newer state:

```dart
@override
Future<void> execute(RereadMediaEvent event) => guardEntity<String, void>(
  event.mediaId,
  read: (b) => b.state.mediaStatus,
  write: (s) => bloc.state.copyWith(mediaStatus: s),
  groupsToRebuild: {GleaningGroups.review, GleaningGroups.detail},
  action: () async {
    final media = bloc.state.reviewItems.firstWhere((m) => m.id == event.mediaId);
    final text = await bloc.service.rereadMedia(media, event.hint); // may throw
    if (text.isEmpty) return;
    emitUpdate(  // the action's own emit — composes with the surrounding guard
      newState: bloc.state.copyWith(reviewItems: [
        for (final m in bloc.state.reviewItems)
          m.id == media.id ? m.copyWith(gleanedText: text) : m,
      ]),
      groupsToRebuild: {GleaningGroups.review},
    );
  },
);
```

The two-emit dance and the `try/finally` disappear; a thrown re-read now lands as `EntityFailure` on exactly that row.

---

## Reading status in widgets

`EntityStatus.when` gives the same ergonomics as `StreamStatus.when`, scoped to one item. Local UI state (controllers, which-row-is-editing) stays in `JuiceWidgetState`; only the *async status* comes from `EntityStatuses`.

```dart
final status = bloc.state.mediaStatus.statusOf(m.id);

// dim the reading while this row works
Text(m.gleanedText ?? '',
  style: theme.textTheme.titleMedium?.copyWith(
    color: status.isWaiting ? scheme.onSurfaceVariant : scheme.onSurface));

// the row's whole control region, driven by its status
status.when(
  waiting: () => const _Rereading(),                    // spinner + label
  failure: (_) => _RereadFailed(onRetry: () => _retry(m)), // ← new capability
  idle: () => hinting ? _HintField(...) : _Actions(...),
);
```

`_RereadFailed` — the per-row error + retry the old single id could not express:

```dart
Row(children: [
  Icon(Icons.error_outline, size: 16, color: scheme.error),
  const SizedBox(width: 8),
  Expanded(child: Text("couldn't re-read this one",
      style: theme.textTheme.bodySmall?.copyWith(color: scheme.error))),
  TextButton(onPressed: onRetry, child: const Text('Retry')),
]);
```

---

## Rebuild granularity (keyed groups)

`EntityStatuses` is orthogonal to *which widgets rebuild*. By default a status change emits the collection's group and the whole list rebuilds (fine for short lists with `const`/`RepaintBoundary` children).

For per-row rebuilds, emit a **keyed group** — the same pattern the framework uses internally (`ScopeGroups.byId(id) => 'scope:id:$id'`). Make each row its own `StatelessJuiceWidget` bound to `{collectionGroup, 'item:$id'}`, and have `guardEntity` (via `groupsToRebuild`) emit `'item:$id'`. Only the spinning row repaints — per-item reactivity with **zero per-item blocs**.

```dart
class _ReviewCard extends StatelessJuiceWidget<GleaningBloc> {
  _ReviewCard(this.id, {super.key})
      : super(groups: {GleaningGroups.review, 'review:item:$id'});
  final String id;
  @override
  Widget onBuild(BuildContext context, StreamStatus _) =>
      _card(context, bloc.state.mediaStatus.statusOf(id) /* ... */);
}
```

---

## Relationship to StreamStatus

| | `StreamStatus` | `EntityStatus` |
|---|---|---|
| Grain | the whole bloc | one entity in a collection |
| Lifetime | one transient transition | persistent until cleared |
| Cardinality | exactly one current | many, concurrent |
| Lives in | the stream (transient) | `BlocState` (persistent) |
| Set by | `emitWaiting/Update/Failure/Cancel` | `guardEntity` / `EntityStatuses` mutators |
| Read by | `onBuild`'s `status` param | `bloc.state.<field>.statusOf(key)` |

**Why not make `StreamStatus` per-key?** It would muddy the clean "one bloc, one current transition" model that every widget binding and `status.when` relies on, and complicate emit semantics. The set of in-flight per-item operations is legitimately *state*; keeping `StreamStatus` bloc-grained and adding entity status as a state value type keeps both concepts sharp.

---

## What this is NOT

It is **not** a bloc (even leased) per list item — the Riverpod-`family` shape. That conceptually gives each row its own real `StreamStatus`, but N blocs for N scrolling rows is real lifecycle + render cost (and a documented scroll-perf hazard). `EntityStatuses`-in-state + keyed groups deliver the same per-item reactivity for a fraction of the cost.

---

## API Summary

```dart
// Value types (lib/src/bloc/src/entity_status.dart)
sealed class EntityStatus { bool get isIdle/isWaiting/isFailure; }
class EntityIdle / EntityWaiting / EntityFailure(error)
extension EntityStatusX on EntityStatus { when(...); maybeWhen(...); }
class EntityStatuses<K> {
  statusOf / isWaiting / isFailure / anyWaiting / waitingKeys / failedKeys
  isEmpty / isNotEmpty / length
  waiting(k) / failure(k, e) / idle(k) / clear()
}

// Use-case helper (BlocUseCase)
Future<T?> guardEntity<K, T>(K key, {read, write, action, groupsToRebuild, rethrowOnError});
```

Exported from `package:juice/juice.dart`.

---

## Guarantees

1. **Cleanup is guaranteed.** `guardEntity` clears to idle on success and records failure on throw — the busy flag can never leak.
2. **Immutability.** Every `EntityStatuses` mutator returns a new instance; the previous state is untouched.
3. **Idle == absent.** The map only holds active (waiting/failed) keys; size tracks in-flight work, not collection size.
4. **Value equality.** Status changes yield distinct states; unchanged maps compare equal (safe for `skipIfSame` / `onStateChange`).
5. **Composition.** `read`/`write` re-read current state each step, so the guarded `action`'s own emits are preserved.
6. **No state-shape coupling.** A bloc may hold any number of independent `EntityStatuses` fields; `guardEntity` locates them via closures.

---

## Design decisions & open questions

- **`read`/`write` closures vs. a `HasEntityStatuses` marker mixin.** Chosen: closures — a bloc can carry several independent status maps, at the cost of a little call-site verbosity. A marker mixin would be terser but limits a state to one map. *Open: revisit if the closure form proves noisy in practice.*
- **`idle` = remove vs. store `EntityIdle`.** Chosen: remove, to bound map size. Trade-off: you can't distinguish "never touched" from "completed" — acceptable, since both are semantically idle.
- **No `canceling` variant (yet).** `StreamStatus` has one; entity-grained cancel hasn't been needed. Add `EntityCanceling` + `guardEntity` cancellation if a real case appears.
- **Failure payload is `Object`.** Mirrors `emitFailure`. Widgets typically show a generic message + retry; the raw error is available if needed.

---

## Testing

Pure value-type tests need no harness; `guardEntity` is covered with a self-contained bloc:

- `EntityStatuses`: default-idle, waiting/failure/idle transitions, `anyWaiting`/`waitingKeys`/`failedKeys`, independence across keys, value equality, idle-no-op.
- `EntityStatus.when` / `maybeWhen` dispatch.
- `guardEntity`: waiting *during* the action (held open with a `Completer`), idle on success, `EntityFailure` (with the thrown error) on throw.

See `test/bloc/entity_status_test.dart`.

---

## Migration

`String? rereadingId` (or `Set<String> busyIds`) → `EntityStatuses<K>`:

```dart
// before
final String? rereadingId;
state.copyWith(rereadingId: id);          // busy
state.copyWith(rereadingId: null);        // done (manual; easy to skip on error)
final busy = state.rereadingId == id;     // widget

// after
final EntityStatuses<String> mediaStatus;
guardEntity(id, read: ..., write: ..., action: ...);   // busy → done/failure, safe
final status = state.mediaStatus.statusOf(id);          // widget: .when(idle/waiting/failure)
```

The widget gains a `failure` branch for free.

---

## File Structure

```
packages/juice/
  lib/src/bloc/src/entity_status.dart   # EntityStatus, EntityStatuses, EntityStatusX
  lib/src/bloc/src/bloc_use_case.dart   # guardEntity
  lib/src/bloc/bloc.dart                # export entity_status.dart
  test/bloc/entity_status_test.dart     # value-type + guardEntity tests
  doc/ENTITY_STATUS_SPEC.md             # this document
```

---

## Spec Version

- **v0.1** — initial draft. `EntityStatus` (idle/waiting/failure), `EntityStatuses<K>`, `guardEntity`. In-app trial in Glean (review re-read flow). Not yet published; API may change before it lands in a release.
