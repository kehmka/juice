# Juice vs the Flutter ecosystem — September 2026

**What this is.** A complete comparison of Juice against bloc, Riverpod, the
signals family, the remaining sophisticated approaches (MobX, redux and
async_redux, stacked, rearch, get_it, command patterns), and the ecosystem's
developer-experience tooling — to find gaps to close, functionality worth
having, and sophisticated mechanisms worth bringing in. Five independent
deep-dives ran in parallel against the same baseline and schema
([doc/comparison/2026-09/](comparison/2026-09/)); this document adjudicates
their claims against Juice's source and ranks what survives. Method note: the
brief given to the researchers itself contained one error (it listed
`sendForResult` as a core API); the researchers caught it, which is the point
of grounding every claim in a grep.

**The one-paragraph verdict.** Juice's model is not behind. All five reports,
independently, credit the same things Juice does better than the family they
studied: rebuild edges that have names (`groups`), concurrency declared per
event, semantic lifecycles with a cleanup barrier and leak detection, paired
telemetry spans rendered in a shipped DevTools extension, per-entity status
with guaranteed cleanup, opt-in cancellable retry, first-class bloc-to-bloc
relays, `send()` that awaits processing, seams-with-fakes as a family rule,
and agent-readable doctrine that travels. What the ecosystem has that Juice
does not is concentrated in four places: **things it re-derives per package**
(state hydration, stream binding, event-returns-a-value), **enforcement that
is still prose** (the lint rules the AGENTS gotchas imply), **tooling hosts
that moved** (Dart's official analyzer-plugin API; pub's package-skills
channel), and **explanation** (a DevTools view that shows why a widget
rebuilt). And two items on Juice's own roadmap turned out to already exist.

---

## 1. Corrections to Juice's own record

These cost nothing and change what the roadmap says.

1. **Teed-up item #2 (select-style rebuilds) is already built.**
   `JuiceSelector<TBloc, TState, T>`, `JuiceSelectorWith` and `bloc.select`
   exist in `packages/juice/lib/src/bloc/src/state_selector.dart`, dedupe by
   `==` (or a custom `equals`), are exported and documented under
   `doc/widgets/`. The roadmap calls the idea "parked". Three things are
   true of the existing implementation: it has **zero tests**, AGENTS.md
   never mentions it, and it **bypasses groups** — it maps `status.state`
   off the raw bloc stream, so a selector rebuilds on every emission's
   value change regardless of which group fired. Decision needed: keep
   (add tests, a `groups:` filter so it lives inside the vocabulary, an
   AGENTS §3 bullet) or deprecate. Found by two of five reports and by the
   author's own inventory. Same shape as item #4 (`skipIfSame`) in August.
2. **"An event that returns a value" exists four ways.** Core has an
   abstract `ResultEvent<TResult>` (`lifecycle/scope_events.dart`) with no
   awaiting helper; `juice_storage` ships the complete trio
   (`StorageResultEvent`, `sendForResult` / `sendAndWaitResult`,
   `OperationResult`) as its own; `juice_forms` puts bare `Completer<bool>`
   fields on events; `juice_permissions` keeps a completer map; network,
   llm, notifications, i18n and auth_network each roll a variant. This is
   the no-parallel-paths rule, violated inside the family. The fix is a
   promotion, not an invention: storage's trio into core, the others
   migrated. Gate: a side-by-side of the four and sign-off on the
   `OperationResult` shape.
3. **A hot-reload gotcha nobody wrote down.** `BlocScope._entries` is
   static, so blocs and state survive hot reload and `execute()` edits
   apply — but builders are registered once at construction
   (`juice_bloc.dart`), so a newly added `UseCaseBuilder` needs a hot
   restart. One AGENTS gotcha.
4. **`JuiceExceptionWidget` has no release-mode gate.** Verified: nothing
   under `packages/juice/lib/src/ui` checks `kReleaseMode`. Whether the
   copy-to-clipboard error card should render in production is a doctrine
   call (fail loud says perhaps yes), not a build. Decide and document.

## 2. Ranked candidates

Each carries the gate that must precede building, per the standing rule that
decisions flow doctrine → built → observed, never from a comparison alone.
Cost S/M/L. "Reports" = which of the five raised it; convergence across
independent reports is the strongest signal this exercise can produce.

### Tier 1 — distribution and enforcement (cheap, high leverage)

**A. Ship the skill through pub's package-skills channel.** Verified on
dart.dev: a package that carries `skills/<package>-<name>/SKILL.md` has it
bundled by `dart pub publish`, and consumers install with
`dart run skills@ get` into Claude Code, Cursor, Gemini, Cline and Copilot.
Juice's bundle lives at the monorepo root as `skills/juice/`, which the
installer's prefix rule skips — today only Claude-marketplace users get it.
Have `tool/sync_skill.sh` emit a second copy at
`packages/juice/skills/juice-framework/` (SKILL.md + references), covered by
the same drift check. Cost S. Gate: prove `dart run skills@ get` accepts the
name on a scratch consumer. Reports: dx.

**B. Port `juice_lint` to Dart's official `analysis_server_plugin`.**
Verified on pub.dev: 0.3.23, Dart ≥ 3.10 (local is 3.12), reports
diagnostics through `dart analyze` and `flutter analyze`, supports quick
fixes and assists. That closes the limitation found while dogfooding
(custom_lint's rules never reach the CLI) and removes the deprecated-API
pins the rule files carry. The dx report also claims custom_lint's README
says it is no longer under active development; **unverified** — the pub.dev
page says no such thing, only that 0.8.1 is twelve months old. The port
stands on the CLI reporting alone. Add the first quick-fix (insert `final`).
Cost M. Gate: the planted-sentinel proof from docket item 5, re-run under
the new host. Reports: dx.

**C. The lint rules the gotchas imply — after B.** Convergent across three
reports, ranked by how many raised each: `juice_stale_read_across_await`
(the documented #1 latent bug; bloc, riverpod, signals),
`juice_missing_concurrency_mode` (codifies the migration just completed;
riverpod, signals), `juice_send_in_build` (signals),
`juice_nullable_copywith_sentinel` (gotcha 6; riverpod),
`juice_lease_in_build` (riverpod), `juice_feature_bloc_dependency` (ROADMAP
invariant 2; bloc), `juice_public_state_field` (bloc). Each rule gated on an
`expect_lint` fixture that reproduces a documented incident, and zero false
positives across the 28 packages. Publish `juice_lint` only after one rule
catches something real in a consumer. Cost M.

**D. `fix_data.yaml` for the three `@Deprecated` members** (`RelayUseCaseBuilder`
→ `StateRelay`/`StatusRelay`, two in `bloc_event.dart`) with a `test_fixes/`
golden, so `dart fix` migrates consumers before the v2.0.0 removal. Cost S.
Gate: confirm the removal list. Reports: dx.

### Tier 2 — mechanisms the family re-derives per package

**E. State hydration as a seam.** `StatePersistence<TState>` in core with a
built-in `hydrate` (sequential, restore as an honest `WaitingStatus`, save
only on `emitUpdate` touching the persisted fields, decode failures loud), a
`juice_storage` default and an in-memory fake, and **versioned, fail-loud
migration** where hydrated_bloc silently overwrites — the one place the
port must differ from its source. Three packages hand-roll load-on-init /
save-on-change today (theme, i18n; sync's outbox store is a different
thing). Cost M. Gate: migrating `juice_theme` and `juice_i18n` must
net-delete code; if the diff doesn't shrink, the abstraction is wrong.
Reports: bloc, riverpod (independently, same shape).

**F. `bindStream` on `BlocUseCase`** (bloc's `emit.forEach`): a helper whose
future ends on stream-done, `CancellableEvent.cancel`, or bloc close,
emitting through `emitUpdate` so groups and telemetry stay intact, and
asserting no binding outlives a non-stateful builder. Five packages
hand-roll `listen` + cancel-in-close (location, llm, realtime,
connectivity, lifecycle). Also the enabler for `restartable`: a superseded
run's bindings die with its epoch. Cost M. Gate: migrate `juice_location`
and `juice_llm`'s generation; their subscription fields and `close()` bodies
must shrink, verified under `LeakDetector`. Reports: bloc.

**G. `juiceTest` and dogfood `BlocTester`.** The tester exists
(`testing/bloc_tester.dart`), sleeps a fixed 10 ms, and **no package test
uses it**. bloc's story is one declarative function with a diff. Add
`seed`, `expect` as a status-type sequence, `expectGroups`, `errors`,
close-before-assert, a leak check. Cost M. Gate: port `juice_theme` and
`juice_sync`; keep it only if the `settle()` calls disappear and the tests
assert group targeting the current ones don't. Reports: bloc, dx.

**H. Small status ergonomics.** `WaitingStatus.progress` (llm downloads,
media uploads) and per-event-type reads from the executor —
`status.isWaitingFor<SubmitEvent>()`, `isRunning(Type)`,
`lastFailure(Type)` — so widgets stop pattern-matching `status.event` and
`juice_permissions` can delete its `requestsInFlight` map. Cost S. Gate:
`juice_llm` model acquire as the progress consumer; the per-type reads ship
only if permissions' map becomes deletable. Reports: riverpod, others.

### Tier 3 — explanation and ergonomics (each on a measurement gate)

**I. DevTools: rebuild inspector + state diff + emission rate.** Juice's
stated differentiator ("groups make rebuild tracing more explainable than a
graph") is not rendered anywhere: the panel shows last groups and a
`toString`. Log a `widget_rebuild` event from the accept path of
`denyRebuild`, diff `oldState → state` (both already on `StreamStatus`),
show groups fired × widgets subscribed and a per-bloc emission sparkline.
New core instrumentation: approve the event schema and measure overhead
first. Cost M. Gate: build it when the select measurement (item #2's
original gate) is actually attempted, so the panel meets a real storm.
Reports: riverpod, signals, dx, others (four of five).

**J. Widgets re-subscribe on every parent rebuild.** `JuiceWidgetState`
builds `_bloc.stream.where(...)` inside `build`, so a parent rebuild cancels
and re-listens (correct, but a cost in lists). Cost S. Gate: a widget test
counting `listen()` calls, before and after. Reports: signals.

**K. Lease `linger` window.** `_releaseLease` closes a leased bloc
synchronously on the last release, so back-navigation to a leased detail
screen rebuilds cold and a route transition can dispose-and-recreate in one
frame. One duration on the existing `register`, loud logs on start / expire
/ reclaim. Cost S. Gate: a measured cold re-entry in Amoli; no consumer, no
knob. Reports: riverpod.

**L. `BlocScope.whenReady` / `allReady` and a test-only `override<T>()`.**
get_it's ordered-init and scope-shadowing, mapped onto the container Juice
already has. Cost S. Gate: count ordered init awaits across the five example
apps first; if there are few, skip. Reports: others.

**M. A `juice_feature` mason brick.** AGENTS §2 is the template in prose and
the skill teaches it; nothing generates it. Cost M, and a maintenance
burden for one maintainer — the brick becomes a second statement of the
canonical shape. Gate: regenerate `notes_app`'s feature and diff to zero;
if the brick drifts from AGENTS §2 once, delete it. Reports: others, dx.

### Still parked, now externally validated

**`restartable`** (teed-up #3): two implementations confirm the roadmap's
design verbatim — bloc_concurrency's `switchMap` cancelling a synchronous
controller whose `onCancel` marks the emitter done, and BlocSignal 1.3.0's
generation-token emission fence — both fence emissions and never roll back
side effects. Build to the roadmap text when a consumer appears; `bindStream`
(F) is the enabler. **A `lane` key on the concurrency knob** for cross-type
FIFO (bloc): its gate is nearer than it looks — `juice_sync`'s documented
Retry↔Discard window is the waiting defect — but still needs a consumer of
juice_sync to exist.

## 3. Rejected, by consensus

Auto-tracked dependency graphs, `computed`, `batch`, `untracked`,
`linkedSignal` (the groups vocabulary is the product; a graph is a parallel
invalidation path). `Cubit` (eventless emit vs one use case per event).
Bloc-wide `==` dedup (per-call `skipIfSame` was chosen for the
waiting→waiting reason). `BlocProvider` trees and `BlocListener` (BlocScope
lifecycles and relays are strictly more explicit). Default-on automatic
retry (hides failures; `RetryableUseCaseBuilder` is opt-in and richer).
`@riverpod` and any Juice codegen (a second truth; Dart macros are cancelled
and augmentations do not change the calculus). Riverpod `Mutation` objects
(the event is the mutation). `ProviderObserver` (the logger taxonomy is a
superset). Redux middleware and time-travel (interception outside the use
case; replay needs pure reducers and use cases call seams). get_it /
injectable (a second resolution path beside BlocScope). fpdart / dartz (a
second error channel beside `FailureStatus`). flutter_hooks and
mixin-as-container. hydrated_bloc's overwrite-on-error default (the silent
fallback the house rule forbids). DevTools time-travel, docs.page, an
umbrella CLI, mock-bloc helpers, goldens.

## 4. What the comparison says Juice should keep saying about itself

The calibration sections of all five reports agree, unprompted, on the same
list. Named rebuild edges. Concurrency as a declared property of the event,
now explicit across every builder in the family. Lifecycles that mean
something (permanent / feature / leased) with a cleanup barrier and leak
detection, versus cache eviction. Telemetry that pairs starts and ends with
an execution id and renders in a first-party DevTools extension bloc still
lacks. Per-entity status with guaranteed cleanup. Retry as an opt-in,
cancellable decorator. Bloc-to-bloc as first-class relays where bloc's
doctrine says "avoid at all costs". `send()` that returns the processing
future. Seams with shipped defaults and fakes as a rule, not a suggestion.
Doctrine that travels with the code. These are the things to protect while
closing the gaps above.
