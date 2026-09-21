# Fine-grained reactivity (signals / solidart / BlocSignal / flutter_hooks / state_beacon) vs Juice

## 1. Family snapshot (versions read, URLs, one-paragraph philosophy)

Read 2026-09-16. **signals 7.1.0** (pub.dev/packages/signals; signals_core 7.0.0, signals_flutter 7.1.0, signals_lint 7.1.0, signals_hooks 7.1.0; core is now the separate **preact_signals 7.0.0** package, "Complete Dart port of Preact.js Signals"; algorithm per preactjs.com/blog/signal-boosting). **solidart 2.8.6** (pub.dev/packages/solidart, depends on `alien_signals ^0.5.4`; flutter_solidart; solidart_lint 3.0.1). **state_beacon 3.1.2** (pub.dev/packages/state_beacon, 21 days old; node-coloring per milomg.dev, github.com/jinyus/dart_beacon). **flutter_hooks 0.21.3+1** (13 months old). **BlocSignal**: bloc_signals 1.4.0, bloc_signals_flutter 1.3.1 (both 5 days old), bloc_signals_lint 1.3.0, bloc_signals_devtools 1.0.0+1 (github.com/RandalSchwartz/BlocSignal) — 12 packages now. Juice baseline: juice 1.7.2 at /Users/kevinehmka/dev/juice.

Philosophy: state is a graph of nodes (`signal` → `computed` → `effect`/widget); reads inside a tracked scope register edges automatically; a write walks the graph and re-runs only what depends on it. Precision is a by-product of the graph, not of a name. BlocSignal keeps the bloc container (events, handlers, transformers) but makes `state` a `ReadonlySignal`, so "emit() updates state immediately in the exact same frame without microtask delay" (pub.dev/packages/bloc_signals). flutter_hooks is orthogonal: composition of widget-local lifecycle logic by call order, not reactivity.

## 2. Mechanism catalog

### signal / computed graph with versioned lazy pull (Preact algorithm; solidart and state_beacon use the SolidJS/reactively colouring variant)
- **What it does / problem solved**: derived values recompute only when a read happens AND an upstream changed; no manual invalidation.
- **How it works**: each dependency edge is one Node linked into two doubly-linked lists (the dependent's sources, the signal's targets) so subscribe/unsubscribe are O(1). Every plain signal write bumps its own version and a global version; a `computed` caches the global version it last saw and skips outright if unchanged, else walks its sources in first-use order comparing versions, and only then runs its function — bumping its own version only if the result differs by equality (signal-boosting blog; preact_signals `Computed` docs: "lazily evaluated", unused branches "automatically pruned"). A computed only subscribes to its sources while it has targets, so orphaned computeds are GC-able. state_beacon instead colours nodes (clean/check/dirty) and its derived "will only compute their value when accessed, subscribed to or being watched"; 3.1.2 fixed "derived would remain in dirty state and stop propagating changes" — the algorithm is still shaking out.
- **Juice today**: `lacks` a graph, deliberately. Derived values are (a) computed inside the use case at emit time and stored in state, (b) getters on the immutable state (recomputed each read, no memo), or (c) `bloc.select`/`JuiceSelector` at the leaf (`packages/juice/lib/src/bloc/src/state_selector.dart`), which re-runs the selector on EVERY status and dedups by `==`. Cross-bloc derivation = `StateRelay` into a state field (`use_case_builders/src/state_relay.dart`).
- **Gap value**: Med for apps with many cheap derived views over one state; Low for Juice's typical shape (state is precomputed per event).
- **Adoption sketch**: without a graph, the honest value is "memoize a derivation on the state instance": precompute in `copyWith`, or a `late final` on the immutable state. No package change. S.
- **Doctrine fit**: conflicts — a tracked graph is the parallel invalidation path groups exist to avoid. Where the answer is "only with a graph" (lazy multi-source memo with auto-pruning), say so: it is, and Juice should not.

### batch / glitch-freedom / effect scheduling
- **What it does**: N writes → one downstream run; readers never observe an intermediate (glitched) combination.
- **How it works**: preact_signals keeps a batch depth; effects notified during a batch are chained on a `nextBatchedEffect` list (no allocation) and run when the outermost batch closes; "if the receiving end ... has already been notified before, and it hasn't yet had a chance to run, then it won't pass the notification forward" (cascade dedup). Reads inside the batch pull lazily so "we'll only update the necessary dependencies to get the current value" (preact_signals README). solidart: `batch` "will not side-effect until its top-most batch is completed". state_beacon differs: "Effects are not synchronous, their execution is controlled by a scheduler" — microtask by default, a 60fps scheduler option, `BeaconScheduler.flush()` in tests.
- **Juice today**: `has-under-another-name` for the glitch half, `lacks` batch. One `emitUpdate` = one whole-state snapshot on a `StreamController.broadcast()` (`core/state_manager.dart`); a widget can never see half a state. Multi-emit in one use case yields N stream events; widget-side, `JuiceAsyncBuilder` sets a `ValueNotifier` per event and Flutter's frame coalesces the `markNeedsBuild`s — batching for free at the widget layer. Cross-bloc (relay) derivation is NOT glitch-free: the destination bloc sees each intermediate source state as a separate event — that is by design (events are the audit trail).
- **Gap value**: Low.
- **Adoption sketch**: none needed. Note only: Juice delivery is a microtask later (non-sync broadcast controller), BlocSignal's is same-frame synchronous. Not observable in practice.
- **Doctrine fit**: fits as-is.

### untracked / peek
- **What it does**: read a signal inside a tracked scope without adding an edge.
- **How it works**: sets a global "no tracking" flag for the callback; `peek()` reads `_value` bypassing the dependency hook. BlocSignal exposes the same idea as `context.state<T,S>()` — "lookup without triggering rebuild dependencies" (bloc_signals_flutter 1.3.0).
- **Juice today**: `has-under-another-name (bloc.state / BlocScope.peekExisting)` — every Juice read is untracked because nothing tracks; subscription is by group set only.
- **Gap value**: none. **Adoption**: n/a. **Doctrine fit**: n/a — the problem does not exist without a graph.

### Async signals: FutureSignal / StreamSignal / AsyncState (solidart `Resource`, beacon `Beacon.future`)
- **What it does / how it works**: a future/stream as a node with loading/data/error; `refresh` keeps data and sets `isLoading`, `reload` resets to loading; a `dependencies` list re-runs the future; lazy start; `autoDispose` on last unsubscribe (signals_core `FutureSignal` docs). state_beacon adds `shouldSleep` (unsubscribe when unwatched, resubscribe on access).
- **Juice today**: `has`: `StreamStatus` waiting/failure/canceling carries the state ("refresh keeping data" = `emitWaiting(newState: state)`); per-row `EntityStatuses` + `guardEntity` (`entity_status.dart`); `JuiceAsyncBuilder` for raw futures/streams; re-run-on-dependency = re-send the event (a relay does it declaratively). Pause-when-unwatched exists only as `JuiceAsyncBuilder(pause:)`.
- **Gap value**: Low. **Adoption**: none. **Doctrine fit**: Juice's version is better aligned (transient vs persistent state is explicit).

### Widget binding: `Watch` → `SignalBuilder`/`SignalWidget`, `.watch(context)`, flutter_solidart `SignalBuilder`, beacon `.watch/.observe`, BlocSignal `context.select`/`buildWhen`
- **What it does**: a widget subscribes to exactly the signals it read during build.
- **How it works**: the builder runs inside an effect-like tracking scope; each `.value` read during the synchronous build registers the element as a target; a change marks the element dirty. signals 7 deprecates `Watch` ("Use SignalBuilder instead"), `SignalsMixin` (→ `SignalWidget`/`SignalStatefulWidget`) and `.watch(context)` (a signals_lint rule flags it); "Only signals accessed synchronously during the execution of the build method are tracked" (SignalWidget docs). BlocSignal: `context.select<B,R>` "rebuilds ONLY when a derived state slice changes", `BlocSignalBuilder(buildWhen:)` (1.2.0), `context.value()` (1.3.0); 1.2.1 fixed select subscription transfer when providers swap above a const subtree — the graph's failure mode is exactly this kind of identity bookkeeping.
- **Juice today**: `has` (`StatelessJuiceWidget` group intersection via `denyRebuild`, `ui/src/widget_support.dart`) plus `partial` select: `JuiceSelector`/`JuiceSelectorWith`/`bloc.select` exist, are exported, documented (`doc/widgets/juice-selector.md`) and used in the root example — but have ZERO tests (`grep -rl JuiceSelector packages/juice/test` → none), are absent from AGENTS.md, and ROADMAP #2 describes select-style rebuilds as unbuilt. Notes: `JuiceSelector` listens to the raw `bloc.stream` (ignores groups) and re-creates its stream on every `didChangeDependencies`; `selectWith` skips `equals` when `previous` is null. Separately, `StatelessJuiceWidget.build` creates a new `b.stream.where(...)` each build, so `JuiceAsyncBuilder.didUpdateWidget` cancels and re-listens on every parent rebuild (correct — broadcast + `initial: currentStatus` — but a cost).
- **Gap value**: Med — not precision (groups give it) but hygiene: an untested half-feature absent from AGENTS is what an AI consumer will reach for.
- **Adoption sketch**: decide `JuiceSelector`: (a) keep — tests, an AGENTS.md bullet (ROADMAP #2's "leaf optimisation inside a group's blast radius"), a `groups:` parameter filtering by group first, `==` second; or (b) deprecate. Package `juice`, S. Resubscribe cost: cache the filtered stream per bloc in the lease holder, S.
- **Doctrine fit**: needs a knob — the ROADMAP already resolved it (groups canonical, select is a leaf optimisation); the code just has not caught up with the decision.

### Effects and listeners (`effect`, `SignalEffect`/`SignalListener`, beacon `.observe`, BlocSignal listeners)
- **What it does**: run a side effect when tracked values change, with a cleanup callback, without rebuilding.
- **How it works**: `effect()` "Creates and immediately executes", returns a disposer; the callback may return a cleanup run before the next execution and on dispose (preact_signals docs). signals 7 moves in-build side effects into `SignalEffect`/`SignalListener` widgets; BlocSignal lints `avoid_unmanaged_signal_effects` because a stray `effect()` is the family's #1 leak.
- **Juice today**: `has-under-another-name`: bloc→bloc = `StateRelay`/`StatusRelay`/`EventSubscription` (`when:` filters, lease-based teardown); widget-side = `onStateChange` (gate), `prepareForUpdate` (`JuiceWidgetState` only, always followed by a build), `JuiceAsyncBuilder(initiator:)`. `partial`: no stateless listener-without-rebuild widget.
- **Gap value**: Low-Med (snackbars/navigation-on-status are usually routed through aviators/routing bloc anyway).
- **Adoption sketch**: `JuiceListener<TBloc>(groups:, onStatus:)` = `StatelessJuiceWidget` with `onStateChange` returning false after the callback. Package `juice`. S.
- **Doctrine fit**: fits (relays-not-listeners covers bloc→bloc; a widget-side status hook is presentation, not logic).

### Disposal and leaks (`autoDispose`, `SignalContainer`, BeaconGroup/BeaconController cascading dispose, hooks disposal by index)
- **How it works**: signals `autoDispose` disposes on the last unsubscribe and throws on later access; state_beacon: "When a beacon is disposed, all downstream derived beacons and effects will be disposed as well"; hooks are disposed when their call-index slot disappears. BlocSignal's DevTools shows "active vs closed container counts and retain warnings".
- **Juice today**: `has`: `BlocLifecycle.permanent|feature|leased`, `FeatureScope` + `CleanupBarrier`, `LeakDetector` (assert-only), emit-after-close throws (`StateManager.emit`). Per-node autoDispose answers a problem Juice solves at the container.
- **Gap value**: Low. **Adoption**: none. **Doctrine fit**: Juice is ahead.

### DevTools extensions
- **How it works**: signals_devtools_extension: dependency graph as a node network plus a list of active signals with values and subscription counts (rodydavis.github.io/signals.dart; site pages themselves 404/timeout today). BlocSignal 1.0.0+1: instance tree (state values, types, closure status), timeline events→transitions→state, interactive `currentState` vs `nextState` diff, leak badge; posted over `dart:developer`. solidart has a filterable signal view.
- **Juice today**: `has` juice_observability 0.4.0 — Timeline (execution/completed pairs with durations, emissions with groups), Blocs (emission count, groups, last event, state summary), Problems; live-verified 2026-09-15 (ROADMAP docket #3). `partial`: no state DIFF view, and no rebuild inspector (which widgets a group emission actually rebuilt) — the thing the ROADMAP calls "MORE explainable than signals' auto-graph" is not yet rendered anywhere.
- **Gap value**: Med-High (this is Juice's stated differentiator).
- **Adoption sketch**: (1) a debug-only `widget_rebuild` log entry on the accept path of `denyRebuild` (widget type, groups matched, event) — the seam already exists; (2) a diff of `oldState` vs `state` (both on `StreamStatus`) in the Blocs tab. Package juice + juice_observability. M.
- **Doctrine fit**: fits; makes the groups position demonstrable.

### Lint packages
- **How it works**: signals_lint 7.1.0: 5 rules (create-in-build, deprecated watch/mixin, naming/options). solidart_lint 3.0.1: 3 assists only. bloc_signals_lint 1.3.0: 20 rules, 9 with quick-fixes — notably `avoid_multiple_synchronous_emits` ("keep transitions atomic"), `avoid_emit_in_build`, `avoid_duplicate_event_handlers`, `avoid_unmanaged_signal_effects`, `avoid_pseudo_events_in_telemetry`.
- **Juice today**: `has` juice_lint 0.1.0 — 3 rules, `publish_to: none`, dogfooded 2026-09-02. `partial`: no rule for the two documented incidents (read-before-await in a `concurrent` use case; a bare `UseCaseBuilder` silently `concurrent` — ISSUES #22) nor for `send()`/`emit` in `build`.
- **Gap value**: Med.
- **Adoption sketch**: `juice_missing_concurrency_mode` (bare builder → info), `juice_send_in_build`, `juice_await_before_stale_emit` (flag `bloc.state` captured before an `await` and used after — heuristic, warn-only). Package juice_lint. M.
- **Doctrine fit**: fits (the AGENTS gotchas as rules — the existing charter).

### BlocSignal since 1.0.1 (what the 08-21 comparison could not see)
- **What changed**: 1.1.0 signal/future→container adapters; 1.2.0 `CubitSignalMixin`/`BlocSignalMixin` so a `ChangeNotifier` or `TextEditingController` can BE a container; 1.3.0 `BlocEventTransformer` receiving the host bloc; 1.4.0 `.value` alias. Flutter: `buildWhen`, `context.value/state`, the select-transfer fix. New packages: otel, hydrate, replay, genui, jaspr.
- **`restartable` verified in source** (`bloc_signals/lib/src/concurrency/event_transformers.dart`): a generation counter — `final currentToken = ++executionToken;` and the emitter is `if (currentToken == executionToken) emit(state)`; "emissions produced by earlier, in-flight handlers whose generation token does not match the latest token are discarded". `droppable` is a bool flag; `sequential` is a `Mutex`. That is exactly Juice's parked ROADMAP #3 design (emission fencing, no rollback), now shipped elsewhere.
- **What the 08-21 read missed**: the atomic-transition doctrine + lint — the mirror image of Juice gotcha #4 (groups accumulate across a multi-emit burst). Juice permits and documents multi-emit; BlocSignal lints against it.
- **Juice today**: `restartable` `lacks` (parked on a consumer); mixin-as-container `lacks` and should stay so.
- **Doctrine fit**: mixins conflict (one bloc shape); restartable fits when a consumer arrives.

### flutter_hooks: `useEffect(keys)`, `useMemoized(keys)`, call-order lifecycle
- **How it works**: "useEffect is called synchronously on every build, unless keys is specified. In which case useEffect is called again only if any value inside keys has changed"; the returned function runs "when the effect is called again or if the widget is disposed". `useMemoized` defaults `keys` to `const <Object>[]` and recomputes when keys differ. Hooks live in a list on the Element by call index — "DON'T wrap use into a condition"; removing one resets everything after it.
- **Juice today**: `lacks`, by design: logic lives in use cases; widget-local controllers use `JuiceWidgetState`.
- **Gap value**: Low. **Adoption**: none (a `juice_hooks` would be a parallel code path). **Doctrine fit**: conflicts.

## 3. Not worth adopting
- Auto-tracked dependency graph / `computed` — the parallel invalidation path groups replace; rebuild tracing by name is the product.
- `batch` — one emit is already atomic; Flutter frames coalesce rebuilds.
- `untracked`/`peek` — meaningless without tracking.
- Per-node `autoDispose` — container lifecycles + CleanupBarrier + LeakDetector own this.
- `linkedSignal` — a use case writing state is the same thing, with an audit trail.
- BlocSignal mixin-as-container — one bloc shape is a locked invariant.
- flutter_hooks — index-ordered lifecycle is fragile and moves logic into widgets.
- state_beacon's async scheduler — reintroduces test-time flushing that synchronous `emit` avoids.
- signals `Watch`/`.watch(context)`/`SignalsMixin` — deprecated in 7 by their own author.

## 4. Top 5 recommendations

1. **Reconcile ROADMAP #2 with the shipped `JuiceSelector`.** The roadmap parks "select-style rebuilds" on a measured rebuild-storm gate, but `JuiceSelector`, `JuiceSelectorWith` and `bloc.select` are already exported from `packages/juice/lib/src/bloc/src/state_selector.dart`, documented in `doc/widgets/juice-selector.md`, used in `example/`, and marked done in `doc/PROPOSED_IMPROVEMENTS.md` — with no test and no AGENTS.md mention. It also bypasses groups (raw `bloc.stream`). Either give it the roadmap's positioning (leaf optimisation, plus a `groups:` filter so it lives inside the vocabulary) with real tests, or deprecate it. Gate: Kevin's call on keep/deprecate; if keep, the rebuild-storm measurement stays the gate for promoting it in docs, but tests and the AGENTS bullet need no gate. Cost S.

2. **Rebuild inspector + state diff in the DevTools extension.** Juice's claim is that named groups make rebuild tracing more explainable than a graph; the panel does not yet show a single rebuild. Log `widget_rebuild` (widget type, matched groups, event, executionId) from `denyRebuild`'s accept path in debug builds, and render `oldState`→`state` diffs (both already on `StreamStatus`) in the Blocs tab — the two things BlocSignal's extension has that Juice's lacks. Gate: the log entry first (it is a seam change in `juice`), verified on the observability example before any panel work. Cost M.

3. **Three incident-derived lint rules.** `juice_missing_concurrency_mode` (bare `UseCaseBuilder` = silently `concurrent`, the ISSUES #22 tail), `juice_send_in_build` (BlocSignal's `avoid_emit_in_build`), and a warn-only `juice_stale_read_across_await` for the #1 latent bug. Gate: each rule ships with an `expect_lint` fixture reproducing the documented incident, and juice_lint stays `publish_to: none` until one fires in a consumer (the existing gate). Cost M.

4. **Stop re-subscribing on every parent rebuild.** `StatelessJuiceWidget._buildAsyncBuilder` builds a fresh `b.stream.where(...)`, so `JuiceAsyncBuilder.didUpdateWidget` cancels and re-listens each time the parent rebuilds. Cache the filtered stream per resolved bloc (in `_BlocLeaseHolder`) or compare source identity. Gate: a widget test asserting one `listen()` across N parent rebuilds, then a before/after on the notes_app list. Cost S.

5. **Keep `restartable` parked, but note the design is now externally validated.** BlocSignal 1.3.0's `restartable` is a generation-token emission fence with no cancellation and no rollback — the ROADMAP #3 semantics verbatim. When a consumer appears (typeahead in Amoli search is the obvious one), build to the roadmap text; do not re-derive. Gate unchanged: a real consumer. Cost S when it comes.

## 5. Things Juice does BETTER than this family
- **One emission = one whole immutable state** — no intra-bloc glitch is possible and there is no graph, versioning or colouring algorithm to get wrong (state_beacon 3.1.2 shipped a "derived stays dirty" fix 21 days ago; BlocSignal 1.2.1 a select-transfer fix).
- **Intent-named, cross-widget invalidation** (`FooGroups.item(id)`) is greppable and explainable to a reader or an AI; a tracked graph needs a DevTools graph view to be explained.
- **Transient vs persistent state is first-class** (`StreamStatus` carrying state; `EntityStatuses` per row with guaranteed cleanup) — the family has `AsyncState` per node and no per-collection story.
- **Lifecycle at the container** (permanent/feature/leased, `CleanupBarrier`, `LeakDetector`, emit-after-close throws) vs per-node `autoDispose` plus lints against creating signals in `build`.
- **Concurrency declared on the builder** with the same three modes BlocSignal has (parity), and a synchronous `emit` that needs no test-time scheduler flush (state_beacon) and no atomic-transition lint (BlocSignal) — multi-emit progress is allowed and documented.
- **Telemetry pairs with `executionId`/`elapsedMicros`** in core; BlocSignal needed a separate lint to keep telemetry names honest.
- **Relays with leases**, not `effect()` closures someone must remember to dispose; **no call-order fragility** (hooks' central hazard).
