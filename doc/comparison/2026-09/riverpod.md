# Riverpod vs Juice

## 1. Family snapshot

**Versions read (2026-09-16):** `riverpod` 3.4.3 (pub.dev, 2026-09-04; CHANGELOG top `## 3.4.3 - 2026-09-04`), `riverpod_generator` 4.0.9, `riverpod_lint` 3.1.9, `riverpod_devtools` 1.1.2 (third-party, github.com/yutsuki3/riverpod_devtools). Docs: https://riverpod.dev/docs/whats_new, `/docs/concepts2/{providers,family,auto_dispose,retry,mutations,offline,observers,overrides}`, `/docs/how_to/{select,testing,cancel,pull_to_refresh}`. Source: `github.com/rrousselGit/riverpod/packages/riverpod/lib/src/core/{element,scheduler,ref,async_value,mutations,persist,provider_container,modifiers/select}.dart`. Juice: `/Users/kevinehmka/dev/juice` (juice 1.7.2).

**Philosophy.** Riverpod models state as a graph of *memoized functions* ("providers"): a body calls `ref.watch(other)`, the container records the edge, upstream change re-runs the body and re-notifies downstream. Caching, disposal, retry, persistence and side-effect status all hang off that node. Remi's stated aims: compile-safety over `BuildContext` lookup, declarative caching, and 3.x's simplification (one `Ref`, one `Notifier`, legacy providers to `legacy.dart`). Juice is the opposite topology — no auto-tracked graph, one bloc per domain, one use case per event, explicit named groups — so the honest question per mechanism is whether its *value* survives translation into events/use cases/groups/seams.

## 2. Mechanism catalog

### `ref.watch` dependency graph + scheduled rebuilds
- **What it does:** a provider or widget declares data dependencies by reading; upstream change re-executes it.
- **How it works:** `ProviderElement` keeps `subscriptions` (what I watch) and `dependents` (who watches me); `ref.watch` is `listen()` whose callback calls `_invalidateSelf(asReload: true)`. Invalidation sets `_mustRecomputeState` and hands the element to `ProviderScheduler.scheduleProviderRefresh`, which batches into one task — end of frame under a Flutter vsync, `Timer(Duration.zero)` otherwise. After rebuild, `updateShouldNotify` (`previous != next` for every provider in 3.x) gates notification. 3.x also mints a new `Ref` per rebuild, pauses the element's subscriptions during the rebuild, and pauses a provider when all its listeners are paused (TickerMode-invisible widgets).
- **Juice today:** `lacks` (by design). Cross-bloc reaction is explicit — `StateRelay`/`StatusRelay`/`EventSubscription` (`use_case_builders/src/{state_relay,event_subscription}.dart`) lease the source bloc and turn its stream into an event; widgets subscribe by group intersection (`ui/src/widget_support.dart::denyRebuild`).
- **Gap value:** Low. The graph's value (never forgetting a consumer) is delivered by groups + relays with a name on every edge.
- **Adoption sketch:** not the graph — the frame batching. Juice rebuilds per emission (`StatusEmitter._emit` → stream → `JuiceAsyncBuilder` → `ValueNotifier`), so a multi-emit use case (AGENTS gotcha 4) rebuilds N times in one frame. A builder-level "one rebuild per frame" coalescer: core, M.
- **Doctrine fit:** graph conflicts (relays not listeners); frame coalescing fits (rendering detail, no knob).

### `select` / `selectAsync`
- **What it does:** rebuild only when a projection of the value changes.
- **How it works:** `provider.select(fn)` returns a `_ProviderSelector` (`ProviderListenable`); on each upstream notification it re-runs `fn`, wraps a throwing selector as `$Result.error`, and notifies only if `lastSelectedValue.value != newSelectedValue.value` (the `==` operator; the selected value must be immutable). `selectAsync` does the same over `AsyncValue` and returns a `Future`. The how_to opens with "benchmark first".
- **Juice today:** `has-under-another-name (JuiceSelector / JuiceSelectorWith / bloc.select())` — `state_selector.dart`, identical semantics (`==` or custom `equals`). ROADMAP "teed up #2" already positions it: groups canonical, select a leaf optimisation, gated on a measured storm.
- **Gap value:** Low. **Adoption sketch:** nothing new. **Doctrine fit:** fits (already resolved).

### `autoDispose` + `keepAlive` links, `onCancel/onResume`
- **What it does:** state dies when unused; per-instance opt-out; time-boxed caches.
- **How it works:** `mayNeedDispose()` schedules disposal when `!isActive && (links == null || links.isEmpty)`; last listener removed → `onCancel` → wait one frame (`await null`) → dispose if still unused. `ref.keepAlive()` pushes a `KeepAliveLink` onto `_keepAliveLinks`; `close()` removes it and re-calls `mayNeedDispose()` when the list empties — hence `Timer(duration, link.close)` is the canonical "cache for 5 minutes". A rebuild clears links. Weak listeners (`weak: true`) don't count toward `isActive`. Codegen defaults to autoDispose; `@Riverpod(keepAlive: true)` opts out; `prefer_keep_alive_annotation` flags a fire-and-forget first-statement `keepAlive()`.
- **Juice today:** `has-under-another-name (BlocLifecycle.leased + BlocLease)` — `bloc_scope.dart::_releaseLease` closes when `leaseCount <= 0`, immediately, plus `permanent`/`feature` (FeatureScope + CleanupBarrier) which Riverpod lacks. `partial`: no linger window — a leased bloc closes on the last release, so back-navigation rebuilds cold and a route transition can dispose/re-create in one frame.
- **Gap value:** Med for navigation-heavy apps.
- **Adoption sketch:** `BlocScope.register(..., lifecycle: .leased, linger: Duration)`: last release starts a timer, a new `lease()` inside the window cancels it, logs `lease_linger`/`lease_linger_expired`; throws if `linger` is given with a non-leased lifecycle. Core, S.
- **Doctrine fit:** needs a knob (`linger`) — one purpose, on the existing registration, not a new mode.

### `AsyncValue` (`isRefreshing`/`isReloading`, `copyWithPrevious`, `guard`, `progress`)
- **What it does:** one sealed value carrying data/loading/error simultaneously, so the UI can show stale data under a spinner or an error over data.
- **How it works:** `AsyncData/AsyncLoading/AsyncError` share private `_value/_error/_loading` slots. On rebuild the element calls `copyWithPrevious(previous, isRefresh:)`: manual `invalidate/refresh` keeps the old value (`isRefreshing = _hasState && isLoading && this is! AsyncLoading`); a `ref.watch`-driven rebuild re-tags it `DataSource.reload` (`isReloading = … && this is AsyncLoading`). `unwrapPrevious()` strips history; `guard(fn, [test])` converts a throwing future to data/error and rethrows what `test` rejects; 3.x adds `progress` (0–1) and seals the class for exhaustive `switch`.
- **Juice today:** `has-under-another-name (StreamStatus + EntityStatuses)`. Every status carries `state` *and* `oldState` (`stream_status.dart`), so `WaitingStatus` never loses data; `FailureStatus` carries `error`/`errorStackTrace` beside state. Per-row: `EntityStatuses.statusOf(k).when(idle|waiting|failure)` with `guardEntity` as the `guard` analogue. `partial`: no `progress`; first-load vs refresh is inferred from state (`items.isEmpty`), not carried.
- **Gap value:** Low–Med (`progress` is real for juice_llm model acquire and juice_media upload).
- **Adoption sketch:** `emitWaiting(progress: double?)` → `WaitingStatus.progress`. Core, S.
- **Doctrine fit:** fits.

### Families
- **What it does:** one definition, one cache entry per argument.
- **How it works:** arguments join the provider identity via `==`/`hashCode` ("Parameters passed need to have a consistent `==`/`hashCode`"; `provider_parameters` lint enforces it). Codegen turns any parameter list (named, optional, generics in 3.x) into a family; docs advise autoDispose on families to stop per-argument leaks.
- **Juice today:** `has-under-another-name (BlocScope scope key + dynamic groups)` — `BlocId(T, scope)` keys instances; `FooGroups.item(id)` / `FormsGroups.field('email')` give per-key rebuilds; `EntityStatuses<K>` per-key status. `partial`: no equality lint on scope keys.
- **Gap value:** Low. **Adoption sketch:** `juice_scope_key_equality` lint (key type overrides `==` or is primitive/enum). juice_lint, S. **Doctrine fit:** fits.

### Dependency overrides for hermetic tests
- **What it does:** replace any provider's body per container/scope.
- **How it works:** `ProviderContainer(overrides: [p.overrideWith | overrideWithValue | overrideWithBuild])`; a `ProviderPointerManager` maps provider→override in O(1) (`orphanPointers`/`familyPointers`); child containers fork the parent's pointers so an overridden provider mounts in the overriding scope. `ProviderContainer.test()` adds `addTearDown(dispose)`; `tester.container()` reaches it in widget tests; `container.listen` keeps autoDispose providers alive.
- **Juice today:** `has-under-another-name (seam injection + BlocScope.reset)` — fakes enter via config (`FooConfig(source: FakeSource())`), tests are headless; `BlocScope.reset()` is `@visibleForTesting` (`bloc_scope.dart:521`). `partial`: no "override only the read" and no scoped override in a widget tree.
- **Gap value:** Low. **Adoption sketch:** none needed; a `BlocTester.withScope` helper pairing register+reset in `addTearDown` would be S ergonomics. **Doctrine fit:** fits.

### `ProviderObserver`
- **How it works:** a list on the container concatenated with the parent's; the element invokes `didAddProvider/didUpdateProvider/didDisposeProvider/providerDidFail` plus 3.x `mutationStart/Success/Error/Reset` with a `ProviderObserverContext`. Third-party DevTools registers as an observer.
- **Juice today:** `has (JuiceLogger taxonomy + DevtoolsJuiceLogger)` — every emission/execution/lifecycle passes through `JuiceLoggerConfig.logger` with typed `context['type']` and paired `executionId` spans with `elapsedMicros`; strictly richer.
- **Gap value:** none.

### Automatic retry (3.x)
- **What it does:** a provider whose build throws is re-run on backoff until success or disposal.
- **How it works:** `ProviderContainer.defaultRetry(retryCount, error, {maxRetries: 10, minDelay: 200ms, maxDelay: 6400ms})` returns `null` for `ProviderException` (an upstream's rethrown error) and any `Error`, else `200ms * 2^n` capped; the element runs `_pendingRetryTimer = Timer(duration, () { _retryCount++; invalidateSelf(asReload: false, manual: false); })`. Overridable on `ProviderScope(retry:)` or per provider. Documented consequence: `await ref.watch(p.future)` swallows intermediate failures until retries are exhausted.
- **Juice today:** `has (RetryableUseCaseBuilder + BackoffStrategy)` — wraps a use case, intercepts `emitFailure`, applies `Fixed/ExponentialBackoff` (jitter, cap), honours `retryOn` and cancellation during backoff, emits the final failure; transport retry in `juice_network`'s idempotency-aware `RetryInterceptor`. Opt-in per event, not default-on.
- **Gap value:** none. Default-on retry is the silent fallback Juice forbids (spinner hides failures for up to ~13 s).
- **Doctrine fit:** Juice's shape is the better fit; do not copy the default.

### Offline persistence (3.x, experimental)
- **What it does:** cache a Notifier's state to disk and restore it on next build.
- **How it works:** `Storage<KeyT, EncodedT>` has `read/write/delete`; `PersistedData` wraps value + `destroyKey` + `expireAt`. Inside `build()`, `persist(storageFuture, key:, encode:, decode:, options: StorageOptions(cacheTime: 2 days default | unsafe_forever, destroyKey:))` reads once, deletes on destroy-key mismatch or expiry, sets `state`, then listens to itself and writes every change. `await persist(...).future; return state.value ?? []` makes it cache-first. Official backend `riverpod_sqflite` (`JsonSqFliteStorage`, `@JsonPersist()`); `Storage.inMemory()` for tests; duplicate keys assert.
- **Juice today:** `partial`. Substrate exists (`juice_storage` with TTL `hiveWrite(ttl:)`/`prefsWrite(ttl:)`), but every package hand-rolls its own seam: `ThemePersistence`, `LocalePersistence`, `SyncStore`, `AuthProvider` session restore, `juice_network` `CacheManager`. No generic "hydrate this field on init, write it on emit" helper (`grep -r persist packages/juice/lib` hits doc comments only).
- **Gap value:** Med — every new package re-implements load/save + seam + fake; destroy-key migrations are ad hoc.
- **Adoption sketch:** `StatePersistence<T>` seam in core (`load/save/clear`) + `hydrate(field:, apply:, encode:, decode:, ttl:, destroyKey:)` on `JuiceBloc` that runs one built-in sequential `HydrateEvent` at init and writes after each `emitUpdate` touching the field. Default `StorageStatePersistence` in `juice_storage` (Hive + TTL + destroyKey), `InMemoryStatePersistence` fake in `juice/testing`. Decode failure → `emitFailure` + clear the key, never keep stale silently. M.
- **Doctrine fit:** fits (seam + default + fake; `ttl` and `destroyKey` each one purpose; fail loud on decode).

### Mutations (3.x, experimental)
- **What it does:** report pending/error/success of a *side effect* to the UI without polluting domain state.
- **How it works:** `final addTodo = Mutation<Todo>()` is a top-level `ProviderListenable<MutationState>`; `addTodo.run(ref, (tsx) async { … tsx.get(p.notifier) … })` flips `MutationPending → MutationSuccess(value) | MutationError(error, stack)`; providers read through `tsx.get` stay alive for the run. UI: `switch (ref.watch(addTodo)) { MutationIdle() … }`. Keyed variants `addTodo(id)` give per-item status; state auto-resets to idle when unlistened, `reset(ref)` manually; observers get mutation callbacks. Marked "may change in a breaking way without a major version bump".
- **Juice today:** `has-under-another-name (StreamStatus per event + EntityStatuses per key)`. The event *is* the mutation: `emitWaiting/emitFailure/emitUpdate` are its states, `status.event` names which event pulsed, `EntityStatuses` + `guardEntity` is the keyed variant with guaranteed cleanup. `partial`: no success *value* on the pulse (`sendAndWait`/`sendForResult` return it to the caller), and a widget asks "is SubmitEvent pending" via `status is WaitingStatus && status.event is SubmitEvent`.
- **Gap value:** Low–Med (one ergonomic read).
- **Adoption sketch:** `status.isWaitingFor<TEvent>()` / `status.failureFor<TEvent>()` extensions. Core, S.
- **Doctrine fit:** fits (no second status holder; the event stays the unit).

### Codegen (`@riverpod`)
- **How it works:** `riverpod_generator` 4.x emits `*.g.dart` with `xProvider` (name configurable in `build.yaml`), `_$X` bases for notifiers, generics in 3.x; `@Riverpod(keepAlive:, retry:)`; "entirely optional".
- **Juice today:** `lacks`, deliberately — no `build_runner` in the family; the canonical five-file shape (AGENTS §2) plus the shipped AI skill bundle (ROADMAP item 6) is the generator.
- **Gap value:** Low. **Adoption sketch:** none (at most a template script, S). **Doctrine fit:** the build_runner tax conflicts with "demonstrate in full"; skip.

### `riverpod_lint` + `custom_lint`
- **What it does:** 16 rules and 6 assists (wrap with Consumer/ProviderScope, convert widget kinds, functional↔class provider).
- **How it works:** AST visitors over `custom_lint_builder`. Generator-only rules enforce the generated shape (`functional_ref`, `notifier_extends`, `notifier_build`, `provider_dependencies`, `scoped_providers_should_specify_dependencies`, `avoid_build_context_in_providers`, `unsupported_provider_value`, `prefer_keep_alive_annotation`, `only_use_keep_alive_inside_keep_alive`); general rules enforce runtime safety (`provider_parameters`, `avoid_ref_inside_state_dispose`, `avoid_public_notifier_properties`, `protected_notifier_properties`, `async_value_nullable_pattern`, `missing_provider_scope`). README claims "quick fixes"; which rules have them is unverified.
- **Juice today:** `has (juice_lint 0.1.0)` — `juice_generic_event`, `juice_mutable_state_field`, `juice_behavior_in_state`, `expect_lint` fixtures, wired into all five example apps (ROADMAP docket #5); no assists, `publish_to: none`.
- **Gap value:** Med. AGENTS documents more enforceable gotchas than rules: the `_unset` sentinel for nullable `copyWith`, `bloc.state` snapshot across an `await` in a `concurrent` use case ("the #1 latent bug"), `BlocScope.lease` outside `initState`, and a builder with no explicit `concurrency` (the family just finished making every builder explicit).
- **Adoption sketch:** `juice_explicit_concurrency`, `juice_stale_state_across_await`, `juice_nullable_copywith_sentinel`, `juice_lease_in_build`; one assist "wrap in StatelessJuiceWidget". M.
- **Doctrine fit:** fits — doctrine made mechanical.

### DevTools story
- **What it does:** core ships hooks (`core/devtool.dart`, `debugTrackProviderCreation` jump-to-source); the panel is third-party `riverpod_devtools` 1.1.2: state inspector with invalidate/refresh from the panel, event log with value diffs, dependency graph from static AST analysis (`RiverpodDevToolsRegistry.loadFromJson`), per-provider update-rate sparklines, load duration, dispose→re-create churn badges, and an optional MCP server.
- **Juice today:** `has (juice_observability 0.4.0 + extension)`: Timeline (executions with ms, emissions with groups), Blocs (emission count, last groups, state summary), Problems — live-verified 2026-09-15. `partial`: no state diff, no rate/churn stats, no send-event-from-panel, no MCP.
- **Gap value:** Med — diffs and group fan-out are the two views that explain a rebuild storm in Juice terms.
- **Adoption sketch:** per-emission state diff (needs a `diagnostics`/`toJson` seam on `BlocState`), a "groups fired × widgets subscribed" view (needs a `widget_subscribed` telemetry entry from `JuiceWidgetState`/`_BlocLeaseHolder`), per-bloc emission-rate sparkline. `juice_observability` + extension, M. MCP later, L.
- **Doctrine fit:** fits.

### Cancellation on dispose / debounce
- **How it works:** `ref.onDispose(client.close)` aborts the request on navigate-away; debounce is `await Future.delayed(500ms); if (didDispose) throw`.
- **Juice today:** `has (CancellableEvent + TimeoutSupport, sendCancellable, emitCancel/CancelingStatus)`; `close()` must cancel its own work (gotcha 8); `restartable` is teed up as ROADMAP #3 with emission-fencing.
- **Gap value:** Low. **Doctrine fit:** fits.

## 3. Not worth adopting

- **Auto-tracked dependency graph** — explicit relays/groups are the point; auto edges hide intent.
- **Default-on automatic retry** — hides failures for up to ~13 s; violates fail-loud. Keep `RetryableUseCaseBuilder` opt-in.
- **`AsyncValue` refresh/reload flags** — only meaningful with a graph; `WaitingStatus` + untouched state already preserves data.
- **`@riverpod` codegen** — build_runner tax against a five-file hand shape the skill bundle teaches.
- **Top-level `Mutation` objects** — the event already is the mutation; a second holder is a parallel path.
- **`ProviderObserver`** — JuiceLogger taxonomy is a superset.
- **Widget-tree scoped overrides** — seams + `BlocScope` scope keys cover it without a container hierarchy.
- **`weak` listeners / pause-on-invisible** — no listener graph to weaken; `JuiceAsyncBuilder.pause` exists if needed.

## 4. Top 5 recommendations

**1. Generic state hydration (`StatePersistence` seam + `hydrate`) — core + `juice_storage`, M.** Four packages hand-roll load-on-init/save-on-change and each new one will too. Riverpod's `persist()` is the right shape to port — key, encode/decode, TTL, destroy-key migration, restore-then-continue — in Juice terms: a seam with a shipped storage default and an in-memory fake, one built-in sequential hydrate event, writes hooked after emits touching the field, decode failures loud. **Gate:** migrate `juice_theme` and `juice_i18n` onto it and delete their bespoke persistence classes; if the diff does not net-delete code, the abstraction is wrong.

**2. Four more `juice_lint` rules (+ one assist) — `juice_lint`, M.** Riverpod puts its runtime contract in the analyzer; Juice's equivalents are prose. `juice_explicit_concurrency` codifies the migration just completed, `juice_stale_state_across_await` targets the documented #1 latent bug, the sentinel and lease rules cover gotcha 6 and the `BlocLease` contract. **Gate:** plant each sentinel in `notes_app` and prove the rule trips (the docket #5 method); publish only after one rule catches something real in Amoli.

**3. Leased-bloc `linger` window — core, S.** `_releaseLease` closes synchronously on the last release, so back-navigation to a leased detail bloc rebuilds cold and a route transition can dispose/re-create in one frame. One duration on the existing `register`, loud logs on start/expire/reclaim. **Gate:** a measured case in Amoli (a leased screen re-entered within seconds); no consumer, no knob.

**4. DevTools: state diff + group fan-out + emission rate — `juice_observability`, M.** `riverpod_devtools` explains rebuilds with diffs, churn badges and a graph; Juice can explain them better because every edge is a named group, but the panel shows only last groups and a `toString`. **Gate:** build it when the select measurement (teed-up #2) is actually attempted, so the panel meets a real storm.

**5. `WaitingStatus.progress` + typed per-event status reads — core, S.** `emitWaiting(progress:)` for juice_llm downloads and juice_media uploads; `status.isWaitingFor<SubmitEvent>()` so widgets stop pattern-matching `status.event`. **Gate:** juice_llm model acquire is the consumer for progress; the per-event read ships only if an example app's submit button needs it.

## 5. Things Juice does better than Riverpod

- **Every rebuild edge has a name.** `groups.intersection(widget.groups)` means a rebuild is explainable by reading two constants; Riverpod needs static analysis plus a DevTools graph to answer "why did this rebuild".
- **Concurrency is a declared property of the event** (`EventConcurrency.sequential/droppable/concurrent`, `event_dispatcher.dart`), audited explicit across the family. Riverpod has no per-operation concurrency model — a `Notifier` method that awaits is exactly the read-before-await race, and the docs' answer is `ref.mounted` checks.
- **Lifecycles are semantic, not cache eviction:** `permanent / feature (FeatureScope + CleanupBarrier with timeout) / leased` vs one autoDispose-with-links; Riverpod has no "this flow ended, tear down its five providers together and await their cleanup".
- **Retry is opt-in, visible, cancellable** (`retryOn`, `onRetry`, cancel during backoff, final failure emitted); Riverpod's default hides failures from `await .future` for ten attempts.
- **Telemetry is a superset of the observer:** paired execution spans with `executionId`/`elapsedMicros`, emissions with groups, `state_emission_skipped`, rendered in a shipped first-party extension; Riverpod's first-party story is hooks only.
- **Per-item status has guaranteed cleanup** (`guardEntity` in a `try/catch`, no stuck spinner); keyed mutations reset only when unlistened.
- **Testing is headless and stream-asserting** (`BlocTester.expectStatusSequence`, emitted `groupsToRebuild` assertable) with hermeticity from named seams and shipped fakes.
- **Leak detection is built in** (`LeakDetector` with creation/lease stack traces, `FeatureScope.debugCheckLeaks`); Riverpod relies on autoDispose defaults and a lint.
