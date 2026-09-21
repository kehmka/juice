# The rest of the sophisticated approaches vs Juice

Baseline read: `/Users/kevinehmka/dev/juice` at `juice 1.7.2` — AGENTS.md, ROADMAP.md, llms.txt, core README, `bloc/src/core/*`, `use_case_builders/src/*`, `bloc_scope.dart`, `lifecycle/*`, `state_selector.dart`, `entity_status.dart`, `testing/bloc_tester.dart`, plus `juice_storage/lib/src/core/{bloc_result_ops,result_event,operation_result}.dart`, `juice_forms/lib/src/forms_bloc.dart`, and the DevTools extension `views.dart`. Every "Juice today" names the file or grep behind it. Dates relative to 2026-09-16.

## 1. Family snapshot (versions read, URLs, one-paragraph philosophy per package)

- **mobx 2.7.0 / flutter_mobx 2.4.0** (~5 days old; https://pub.dev/packages/mobx, /flutter_mobx; source read `mobx/lib/src/core/{reaction,context,computed}.dart`, `flutter_mobx/lib/src/observer_widget_mixin.dart`). Transparent reactivity: observables, `@computed` ("what can be derived, should be derived"), `autorun`/`reaction`/`when`, `Action` as the batching mutation boundary. Dependencies are discovered by reading, never declared.
- **redux 5.0.0 / flutter_redux 0.10.0 / redux_dev_tools 0.7.0** (4–5 years old; https://pub.dev/packages/redux, /flutter_redux, /redux_dev_tools). Single store, pure reducers, `Middleware = (Store, action, NextDispatcher next)`, `StoreConnector(converter, distinct)`. Dormant, but the reference Dart time-travel.
- **async_redux 28.4.0** (~2 days old; https://pub.dev/packages/async_redux, https://asyncredux.com/flutter/basics/wait-fail-succeed/, source read `lib/src/store.dart`). Each action is a class with `before/reduce/after/wrapError`; the store tracks in-flight and failed actions by type so widgets ask `isWaiting(MyAction)`.
- **stacked 3.5.0 / stacked_generator 2.0.4 / stacked_cli** (13 and 3 months; https://pub.dev/packages/stacked, /stacked_generator, https://stacked.filledstacks.com/docs/tooling/stacked-cli). MVVM on `ChangeNotifier`, busy/error keyed by object, get_it underneath, a CLI that scaffolds view+viewmodel+test and edits `app.dart` at marker comments.
- **rearch 1.16.1** (17 months; https://pub.dev/packages/rearch; source read `packages/rearch/lib/{rearch,src/side_effects}.dart`). Capsules are functions of a `CapsuleHandle`; side effects compose; a dataflow graph rebuilds dependents; "idempotent" capsules are disposed automatically.
- **get_it 9.2.1 / injectable 3.0.0** (6 and 4 months; https://pub.dev/packages/get_it, /injectable; README read). Locator with a scope stack, async singletons with `dependsOn`/`allReady`, annotation codegen.
- **fpdart 1.2.0 / dartz 0.10.1** (10 months; dartz 4 years, unverified uploader; https://pub.dev/packages/fpdart, /dartz). `Either`, `Option`, `TaskEither.tryCatch`, Do-notation: failures as values.
- **flutter_command 7.2.2 (discontinued) → command_it 9.5.1** (6 months; https://pub.dev/packages/command_it, https://pub.dev/documentation/command_it/latest/command_it/Command-class.html). A `Command` publishes `value`, `results`, `isRunning`, `canRun`, `errors` as `ValueListenable`s; restriction, error filters, undo, progress.
- **elementary 3.2.1 / elementary_test 2.1.1** (14 months; https://pub.dev/packages/elementary, /elementary_test). MWWM: `ElementaryWidget` → `WidgetModel` → `ElementaryModel`; `EntityStateNotifier`; `testWidgetModel`.
- **very_good_cli 1.5.0 / mason_cli 0.1.4 / feature_brick 0.6.2** (8 days / 19 hours / 3 years; https://pub.dev/packages/very_good_cli, /mason_cli, https://brickhub.dev/bricks/feature_brick, https://cli.vgv.dev/docs/templates/core). Mustache bricks generate a feature folder or a whole app (three flavors, `BlocObserver`, l10n, coverage, CI).

## 2. Mechanism catalog

### Auto-tracked derivations and reactions (MobX)
- **What it does / problem solved**: `Observer` and `reaction` re-run only when an observable they actually read changes; `@computed` caches derived values.
- **How it works**: `Computed` is both `Atom` and `Derivation`; observed, it recomputes only when `_context._shouldCompute(this)` reports a stale dependency and uses `equals` to suppress no-op propagation; unobserved and outside a batch it recomputes on every read. Propagation is two-phase — `propagateChanged()` marks `stale`, `_propagatePossiblyChanged()` marks `possiblyStale` so a computed verifies before observers run. `Action` wraps `startBatch/endBatch`; reactions queue via `addPendingReaction` and run when the batch counter hits zero, guarded by `maxIterations` (100) → `MobXCyclicReactionException`. `Observer` builds inside `reaction.track(() => super.build())`, invalidates via `markNeedsBuild`, warns when `!reaction.hasObservables`.
- **Juice today**: `has-under-another-name` for the widget effect — rebuild groups (`widget_support.dart: denyRebuild`, set intersection) plus `bloc.select`/`JuiceSelector`/`JuiceSelectorWith` (`state_selector.dart`, `==` or custom `equals`). `lacks` computed caching (grep `computed|derived|memoiz` in `packages/juice/lib`: doc comments only).
- **Gap value**: Low for tracking (groups are explicit by doctrine); Med for a memoised projection helper.
- **Adoption sketch**: no graph. Note ROADMAP #2 ("`SelectJuiceWidget` / `.select<T>`") is 📋 while `JuiceSelector` + `bloc.select` already ship — the discoverability situation item #4 turned out to be. Cost S (docs).
- **Doctrine fit**: auto-tracking conflicts; reconciling ROADMAP #2 with the shipped selector fits.

### Per-action-type waiting/failed queries (async_redux)
- **What it does / problem solved**: any widget asks `context.isWaiting(LoadText)`, `isFailed(LoadText)`, `exceptionFor(LoadText)` — no busy flag threaded through state.
- **How it works**: `Store` keeps `HashSet<ReduxAction> _actionsInProgress` (added in `_calculateIsWaitingIsFailed()`, removed in `_finalize()`) and `Map<Type, ReduxAction> _failedActions` written in `_processError()`. `isWaiting(Object actionOrTypeOrList)` matches by `runtimeType` for a `Type`, identity for an instance, any-of for an iterable. Re-dispatching a type clears its failed entry; `clearExceptionFor` clears manually; only `UserException` counts as failed. Types queried are recorded in `_awaitableActions` so the store rebuilds the right widgets. `dispatchAndWait` returns `Future<ActionStatus>` (`isCompletedOk`, `originalError`, `wrappedError`, `hasFinishedMethodBefore/Reduce/After`, `isDispatchAborted`).
- **Juice today**: `partial`. `StreamStatus` is bloc-wide; `EntityStatuses<K>` + `guardEntity` (`entity_status.dart`, `bloc_use_case.dart`) is per-entity, keyed by the app's key not event type. The dispatcher's `_running: Map<Type,bool>` (`event_dispatcher.dart`) is private and set only for `droppable`. `sendAndWait` (`juice_bloc.dart`) resolves on the first non-waiting status of *any* event.
- **Gap value**: Med-High — `juice_permissions` hand-rolls `Map<JuicePermission, Completer<PermissionStatus>> requestsInFlight`; `juice_forms` passes `Completer<bool>` fields on `ValidateFormEvent`/`SubmitFormEvent`.
- **Adoption sketch**: `bloc.isRunning(Type)` and `bloc.lastFailure(Type)` (cleared on next dispatch of that type) maintained in `UseCaseExecutor.execute` around the existing start/end pair, surfaced as an emission so groups can subscribe. Package `juice`, cost M.
- **Doctrine fit**: fits (read-only, no logic leaves the use case); one knob ruling — is `lastFailure` state or status.

### Lifecycle hooks and behavioural mixins (async_redux)
- **What it does / problem solved**: `before/reduce/after/wrapError/wrapReduce/abortDispatch` per action; mixins `NonReentrant`, `Retry`/`UnlimitedRetries`, `Debounce`, `Throttle`, `Fresh` (`freshFor`), `Polling`, `CheckInternet`, `OptimisticCommand`.
- **How it works**: the dispatch pipeline calls hooks in order (`after()` sync-only, always runs); a mixin overrides `abortDispatch`/`wrapReduce` — `NonReentrant` aborts when `isWaiting(runtimeType)`, `Debounce` holds a per-type timer, `Retry` re-runs `reduce` with backoff. `globalWrapError`, `errorObserver`, `actionObservers`, `stateObserver` are store-level lists.
- **Juice today**: `has` concurrency (`EventConcurrency` ≈ `NonReentrant`; `restartable` planned, ROADMAP #3), `has` retry (`RetryableUseCaseBuilder` + `BackoffStrategy`), `has` global error (`BlocErrorHandler`). `lacks` debounce/throttle/fresh/polling (grep `debounce|throttle` in `packages/juice/lib`: none). No `before/after` by design.
- **Gap value**: Med for debounce/throttle (same typeahead consumer as `restartable`); Low for `Fresh`/`Polling` (a timestamp in state).
- **Adoption sketch**: `UseCaseBuilder(debounce: Duration)` implemented in `EventDispatcher` beside `_tails`/`_running`, shipped with `restartable`. Package `juice`, cost M.
- **Doctrine fit**: needs a knob — same gate as `restartable`: a real consumer.

### Middleware chain and observers (redux, async_redux)
- **What it does / problem solved**: cross-cutting logging, persistence, gating on every action without touching reducers.
- **How it works**: each `Middleware` calls `next(action)` to continue or swallow; async_redux replaces the chain with typed observer lists and a `persistor` fed every state change.
- **Juice today**: `has-under-another-name (JuiceLogger + UseCaseExecutor)`. Every execution funnels through `UseCaseExecutor.execute` (start/complete/error sharing `executionId`) and every emission through `StatusEmitter._emit` (`state_emission` with `groups`); `JuiceLoggerConfig.configureLogger` swaps the sink. No way to block or rewrite an event in flight.
- **Gap value**: Low. Observation is richer than redux's; interception conflicts with one-use-case-per-event.
- **Adoption sketch**: none; a persistor is a `StateRelay` into `juice_storage`, which exists. Cost 0.
- **Doctrine fit**: interception conflicts; observers fit and exist.

### Time-travel / undo (redux_dev_tools, command_it)
- **What it does / problem solved**: step through state history in dev; undo a user action at runtime.
- **How it works**: `DevToolsStore` keeps `DevToolsState(computedStates: List<S>, stagedActions, currentPosition)` plus `savedState`/`latestAction`; `DevToolsAction`s move `currentPosition`, and `state` is `computedStates[currentPosition]` — possible only because reducers are pure. command_it's `createUndoable*` takes an undo function and an `UndoStack`, with `undoOnExecutionFailure` rolling back when the handler throws.
- **Juice today**: `lacks` (grep `undo|redo|history|snapshot` in `packages/juice/lib`: none; family hits are `juice_routing`'s stack). The extension has `TimelineView`/`BlocsView`/`ProblemsView` (`views.dart`), no diff or replay (no `Diff` class in `juice_observability*/lib`). Use cases call seams, so replay would re-fire side effects; compensating undo is feasible.
- **Gap value**: Med for a dev-time state ring buffer (`state_emission` already carries `state.toString()`); Low for runtime undo.
- **Adoption sketch**: (a) `juice_observability`: last N `StreamStatus` per bloc in `TelemetryStore`, prev/current side by side, cost S. (b) `UndoableUseCase` mixin returning a compensating `EventBase` pushed on a bounded `UndoStack`; `bloc.undo()` sends it. Cost M, gate on a consumer.
- **Doctrine fit**: (a) fits; (b) needs a knob and a ruling that undo is an event, not a rewind.

### ViewModel busy/error by object; reactive services (stacked)
- **What it does / problem solved**: `setBusyForObject(key)`, `busy(key)`, `runBusyFuture(future, busyObject:)`, `setErrorForObject`, `hasErrorForKey`; `ReactiveViewModel.listenableServices` re-notifies when a `ListenableServiceMixin` service changes.
- **How it works**: `BaseViewModel` keeps busy/error maps keyed by object identity and calls `notifyListeners` around the future; `ReactiveViewModel` attaches `notifyListeners` to each declared service, detaching in `dispose` (API docs; source fetch 404'd — unverified at the implementation level).
- **Juice today**: `has-under-another-name` — `EntityStatuses<K>` + `guardEntity` is `runBusyFuture(busyObject)` with a failure surface and guaranteed cleanup; `StateRelay`/`EventSubscription` replace `listenableServices`.
- **Gap value**: Low. Juice's is strictly stronger.
- **Adoption sketch**: none. **Doctrine fit**: n/a.

### Capsules with graph-derived garbage collection (rearch)
- **What it does / problem solved**: state and logic as composable functions; lifetime derived from the dependency graph, not declared.
- **How it works**: `CapsuleContainer._capsules: Map<_UntypedCapsule, _CapsuleManager>` created via `putIfAbsent`; `use(other)` records an edge in a `DataflowGraphNode`; side-effect state is stored through the primitive `register`; a capsule is disposed when `capManager.isIdempotent && capManager.hasNoDependents` (`asListener` registers an empty effect to pin one). `runTransaction` coalesces updates into "a single container rebuild sweep" (`buildNodesAndDependents`). `use.mutation` returns `(state: AsyncValue?, mutate, clear)`. Flutter: `RearchConsumer.build(context, WidgetHandle use)`.
- **Juice today**: `partial`. `BlocScope` derives lifetime from leases (`leaseCount`, auto-close on last release) and `FeatureScope` — explicit, not graph-derived. No transactional multi-bloc emit; `StateRelay` chains are microtask-delayed.
- **Gap value**: Low-Med. Graph disposal is the novel bit; the lifecycle enum is Juice's deliberate answer. Batching several blocs' emissions into one frame is the piece with UI value.
- **Adoption sketch**: `BlocScope.batch(() {...})` deferring `StateManager` delivery until the closure ends; `state_manager.dart`, cost S-M, gate on an observed double-paint.
- **Doctrine fit**: capsules conflict; batching fits.

### Scope stack, async-ready singletons, codegen registration (get_it + injectable)
- **What it does / problem solved**: `pushNewScope(scopeName:, init:, dispose:, isFinal:)`/`popScope()`/`popScopesTill`/`dropScope`, shadowing, reverse-order disposal; `registerSingletonAsync(dependsOn:, signalsReady:)`, `isReady<T>()`, `allReady(timeout:)`, `getAsync`, `WillSignalReady`; `registerFactoryParam`, named instances, `Disposable`, `resetLazySingleton`. injectable emits `GetIt.init()` from `@injectable`/`@lazySingleton`/`@preResolve`/`@Scope`/`@Order`/`@Environment`/`@postConstruct`/`@disposeMethod`.
- **How it works**: scope frames searched newest-first; async singletons form a wait-graph so `allReady()` completes when every `dependsOn` chain has signalled.
- **Juice today**: `partial`. `BlocScope` registers only `T extends JuiceBloc<BlocState>` keyed by `BlocId(type, scope)` — no services, no names; `permanent/feature/leased`; `FeatureScope` ≈ named scope with `CleanupBarrier` (timeout, failure count) — better than get_it's `dispose`; `leaseAsync` waits on `closingFuture`. No `allReady`: the idiom is `withConfig` sending an `Initialize*Event` (`droppable`). Services travel in `FooConfig` seams. `BlocDependencyResolver`/`CompositeResolver`/`GlobalBlocResolver` already let an app plug get_it or Modular in for bloc resolution.
- **Gap value**: Med. Real pain: (1) no "substrate initialised" gate — apps hand-await `StorageBloc.initialize()` chains; (2) no shadowing — tests cannot override a permanent registration (`register` throws on lifecycle mismatch, else no-ops).
- **Adoption sketch**: (1) `BlocScope.whenReady<T>()`/`allReady()` completed by the init use case's `ResultEvent` (already returned by `InitializeStorageEvent`); (2) `@visibleForTesting BlocScope.override<T>(factory)`. Package `juice`, cost M. Services stay in seams.
- **Doctrine fit**: (1) fits (fail-loud `get<T>()` before ready); (2) needs a knob, test-only.

### Commands as listenables (command_it)
- **What it does / problem solved**: `Command.createAsync(handler, initialValue:, restriction: ValueListenable<bool>, ifRestrictedRunInstead:, errorFilter:, notifyOnlyWhenValueChanges:, debugName:)` exposes `value`, `results: CommandResult(paramData, data, error, isRunning)`, `isRunning`, `isRunningSync`, `canRun`, `errors`; `runAsync()` returns a Future; `createAsyncWithProgress(ProgressHandle)`; `cancel()`; `globalErrorHandler`, `loggingHandler`; `CommandBuilder`; `pipeToCommand()`; `MockCommand`.
- **How it works**: a `ValueNotifier` over the last result; running toggles `isRunning`; exceptions route through an `ErrorFilter` (local listener / global / rethrow) instead of one `catchAlways` bool; `canRun = !isRunning && !restriction`.
- **Juice today**: `partial`. `ResultEvent<T>` (`lifecycle/scope_events.dart`: `succeed/fail/result/isCompleted`) is the typed-return primitive but core has no helper to await it against the status stream; `juice_storage` re-implements it as `StorageResultEvent` (+`requestId`) with `sendAndWaitResult`/`sendForResult`/`OperationResult` (`core/bloc_result_ops.dart`, instance-filtered via `identical(s.event, event)`); `juice_forms` uses bare `Completer<bool>` fields (`validateNow/submitNow`); `juice_permissions` a `Completer` map. Core `sendAndWait` is not instance-filtered. `CancellableEvent` + `TimeoutSupport` exist; restriction ≈ `droppable` + state check; no progress primitive.
- **Gap value**: High. Four "event returns a value" implementations in one family is the clearest "no parallel code paths" violation found.
- **Adoption sketch**: promote `juice_storage`'s trio into core: `ResultEvent` gains `requestId`; `JuiceBloc.sendForResult<T>` / `sendAndWaitResult` (instance-filtered, timeout) in `juice_bloc.dart`; `OperationResult` to core; migrate storage/forms/permissions. Optional `ProgressEvent` mixin via `emitWaiting`. `juice 1.8.0`, cost M.
- **Doctrine fit**: fits every rule.

### Failures as values (fpdart / dartz)
- **What it does / problem solved**: `Either<Failure, T>`, `TaskEither.tryCatch`, `match`/`fold` make the failure type part of the seam signature.
- **How it works**: sum types with `map/flatMap` and Do-notation (`Either.Do(($) => …)`).
- **Juice today**: `lacks` a Result type (grep `Either<|class Result` in `packages/*/lib`: none). Failure travels as `Object? error` on `FailureStatus`, `EntityFailure(error)`, `OperationResult.error`.
- **Gap value**: Low-Med; Dart 3 sealed classes give the same with no dependency.
- **Adoption sketch**: per-package `sealed class FooFailure` on the seam, `FailureStatus.error` typed by convention. Cost S.
- **Doctrine fit**: fits; an FP dependency would add a second error channel.

### WidgetModel triad and lifecycle testing (elementary)
- **What it does / problem solved**: `WidgetModel` with `initWidgetModel/didUpdateWidget/didChangeDependencies/deactivate/activate/dispose`, `onErrorHandle` from `ElementaryModel.handleError`; `EntityStateNotifier` loading/error/content; `testWidgetModel(setupWm, (wm, tester, context) …)` drives the lifecycle against a mocked context.
- **How it works**: the element owns the `WidgetModel`, which owns the model; builders subscribe to `StateNotifier`s.
- **Juice today**: `has-under-another-name` — `StatelessJuiceWidget.onInit/onStateChange/close`, `JuiceBuilder.onInit/onDispose`, `JuiceWidgetState` 1–3; `StreamStatus` = `EntityState`. `BlocTester` covers blocs only.
- **Gap value**: Low, except widget-lifecycle testing.
- **Adoption sketch**: `JuiceWidgetTester` in `testing/` pumping a `StatelessJuiceWidget` under a fake bloc and asserting rebuilds per group. Cost S-M.
- **Doctrine fit**: fits.

### Feature scaffolding (stacked_cli, very_good_cli, mason bricks)
- **What it does / problem solved**: `stacked create view login` writes view + viewmodel + `test/viewmodels/` and inserts the route at `// @stacked-route`/`// @stacked-import`; `very_good create flutter_app` yields flavors, `BlocObserver`, l10n, CI, coverage; `feature_brick` emits bloc/event/state, `view/*_page.dart`, `widgets/*_body.dart`, barrels, tests from `feature_name`/`state_management`/`use_equatable`.
- **How it works**: mason renders `__brick__` mustache with case transforms, `pre_gen/post_gen` Dart hooks, conflict strategies; stacked patches marker comments so registration is automatic but optional.
- **Juice today**: `lacks`. AGENTS.md §2 is the template in prose and the skill (`skills/juice`, `tool/sync_skill.sh --check`) ships it to agents; no brick, no CLI, no `melos run new:package`.
- **Gap value**: High — 24 packages hand-shaped; the 2026-09-15 card-drift audit is the drift a generator prevents.
- **Adoption sketch**: `juice_feature` brick in `tool/bricks/` (vars `feature_name`, `seam`, `lifecycle`, `concurrency` per event) emitting the §2 skeleton, a fake seam, a headless test with `settle()`, an `LLM.md` stub, a `custom_lint` block; a `juice_package` brick for the family. Cost M.
- **Doctrine fit**: fits ("demonstrate in full" becomes generated).

## 3. Not worth adopting

- MobX auto-tracking / `Observer`: replaces the groups vocabulary with implicit dependencies.
- redux middleware `next(action)`: interception outside the use case breaks one-use-case-per-event.
- redux_dev_tools replay: needs pure reducers; Juice use cases call seams.
- rearch capsules / `WidgetHandle`: a different doctrine, not a gap.
- get_it as a service container: seams travel via `FooConfig`; a locator is a second resolution path beside `BlocScope`.
- injectable codegen: nothing to annotate once blocs are the only registered type.
- dartz: unmaintained; fpdart as a dependency: a second error channel next to `FailureStatus`.
- stacked `ReactiveViewModel`/`ListenableServiceMixin`: relays do this without listeners.
- elementary's `WidgetModel` layer: a third class the widget/use-case split does not need.
- command_it `restriction: ValueListenable<bool>`: `droppable` plus a state predicate covers it.

## 4. Top 5 recommendations, ranked

1. **Unify "event returns a value" in core (command pattern).** Promote `juice_storage`'s `sendForResult`/`sendAndWaitResult`/`OperationResult` and `requestId` onto core `ResultEvent`, instance-filter with `identical(status.event, event)`, keep the 30 s timeout loud, then migrate `juice_storage`, `juice_forms` (`Completer<bool>` fields) and `juice_permissions` (`Completer` map). Three parallel paths become one and every bloc gets a typed command surface comparable to command_it's `runAsync()` and async_redux's `dispatchAndWait → ActionStatus`. Gate: show the four implementations side by side and get sign-off that `OperationResult`'s shape is the one; ship as `juice 1.8.0` with all three migrations.

2. **A `juice_feature` mason brick (and `juice_package`).** The canonical shape exists as prose and skill; a brick makes it mechanical and enforces what prose cannot — explicit `concurrency:` on every generated builder, a fake for every seam, an `LLM.md` stub that `tool/check_cards.sh` polices. Gate: generate `notes_app`'s notes feature and diff against the hand-written one — zero semantic diff is the acceptance test; decide `tool/bricks/` vs BrickHub.

3. **Per-event-type running/failure queries from the executor.** `bloc.isRunning(SaveEvent)` and `bloc.lastFailure(SaveEvent)` (cleared on next dispatch of that type, async_redux's rule) computed in `UseCaseExecutor.execute` around the existing `executionId` span and surfaced as an emission. Read-only; no logic moves. Gate: `juice_permissions`' `requestsInFlight` map must become deletable, or don't build.

4. **`BlocScope.whenReady<T>()`/`allReady()` and a test-only `override<T>()`.** get_it's `dependsOn`/`allReady` solves the boot sequencing every Juice app hand-writes; the `ResultEvent` from `Initialize*Event` is the ready signal already. `override` gives tests shadowing without touching `register`'s mismatch throw. Gate: enumerate the boot sequence in the five example apps; if fewer than three await more than one init in order, ship only `override`.

5. **DevTools state history (read-only) and a `JuiceWidgetTester`.** Keep the last N `StreamStatus` per bloc in `TelemetryStore`, show prev/current side by side — the honest subset of time-travel for impure use cases, zero core cost. Pair with a `testing/` helper that pumps a `StatelessJuiceWidget` against a fake bloc and asserts which groups rebuilt — the one test the groups doctrine still cannot write. Gate: publish `juice_observability 0.4.0` first (committed, unpublished — ROADMAP docket #3).

## 5. Things Juice does BETTER than this family

- **Per-event concurrency as a declared mode.** `EventConcurrency.sequential/droppable/concurrent` per type (`event_dispatcher.dart: _tails/_running`), audited across all 24 packages; async_redux needs a `NonReentrant` mixin per action, MobX/stacked/rearch have nothing.
- **Per-entity async status with guaranteed cleanup.** `EntityStatuses<K>` + `guardEntity` carries the error per key and clears on throw; stacked's `setBusyForObject` has no per-key failure surface, command_it tracks one command.
- **Ownership lifecycles with a cleanup barrier.** Leases, `leaseAsync` on `closingFuture`, `FeatureScope.end()` → `CleanupBarrier.wait(timeout)` with failure counts, `LeakDetector`; get_it's `popScope` has no timeout or leak report, rearch's GC is opaque.
- **Emission telemetry as spans.** Start/complete/error sharing `executionId` with `elapsedMicros`, every emission logging its groups, rendered in DevTools; redux logging middleware and MobX `spy` give events, not spans.
- **Named rebuild groups as a reviewable contract.** Which groups a use case emits and a widget subscribes to is readable in source; MobX's tracked set and rearch's graph exist only at runtime.
- **Seams with shipped defaults and fakes as a family rule.** Every vendor boundary is an interface with a default and a fake; the compared packages leave this to the app.
- **Agent-readable doctrine that travels.** AGENTS.md, per-package `LLM.md` cards with drift checks, an installable skill — none of the compared packages ship an equivalent, and it is why every "Juice lacks X" above was grep-verifiable in minutes.
