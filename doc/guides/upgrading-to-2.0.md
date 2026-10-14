---
layout: default
title: Upgrading to 2.0
parent: Guides
nav_order: 99
---

# Upgrading to juice 2.0.0

2.0.0 is the breaking set, shipped together. This guide lists every change
that can stop a 1.x program compiling or alter what it does, with the migration for each, then the new surface. The CHANGELOG has the same list
in release-note form; `benchmarks/RESULTS.md` §15–§17 have the numbers.

Every family package gets a matching major or minor bump that requires
`juice: ^2.0.0` in the release wave that follows the core; upgrade them
together. The wave's versions are listed at the end of this guide.

## Compile-time changes

### `concurrency:` is required on every builder

```dart
// 1.x
() => UseCaseBuilder(typeOfEvent: SaveEvent, useCaseGenerator: () => SaveUseCase()),

// 2.0
() => UseCaseBuilder(
      typeOfEvent: SaveEvent,
      useCaseGenerator: () => SaveUseCase(),
      concurrency: EventConcurrency.sequential,
    ),
```

`UseCaseBuilder`, `UseCaseBuilder.typed`, `StatefulUseCaseBuilder`,
`RetryableUseCaseBuilder` and `InlineUseCaseBuilder` all take it;
`UseCaseBuilderBase.concurrency` is abstract. Pick per event:
`sequential` when the use case mutates shared state, `droppable` for an
exclusive flow (a flush, a connect), `restartable` when the latest input
wins (search, filter, select), `concurrent` for independent events. The
opt-in lint `juice_missing_concurrency_mode` is retired; the compiler asks.

`EventConcurrency` has a fourth value, `restartable`: an exhaustive
`switch` needs the case.

### `UpdateEvent` carries no state and no type parameter

```dart
// 1.x
bloc.send(UpdateEvent(newState: state.copyWith(count: 5)));
typeOfEvent: UpdateEvent<CounterState>,

// 2.0 — a state change is an event a use case handles
bloc.send(SetCountEvent(5));
typeOfEvent: UpdateEvent,
```

`UpdateEvent` re-emits the bloc's current state under the groups, status
or aviator it names. There is no `dart fix` for this on purpose: a 1.x
`UpdateEvent(newState:)` must fail to compile rather than silently become
a no-op. Tests seed a state with `bloc.seedState(state)` (see below).

### The vendored `bloc` base is gone

`Bloc`, `BlocBase`, `Emitter`, `BlocEventSink`, `EventTransformer`,
`EventMapper` and `GlobalBlocResolver` are removed. `JuiceBloc` still
implements `StateStreamableSource`, `Emittable` and `ErrorSink`.

```dart
// 1.x
GlobalBlocResolver().resolver = MyResolver();

// 2.0 — register with the scope; pass a resolver only where an API takes one
BlocScope.register<FooBloc>(() => FooBloc(), lifecycle: BlocLifecycle.permanent);
FooView(resolver: const MyResolver());        // a widget that resolves elsewhere
```

### `JuiceLogger` gains `record`

Every logger implementation needs the new method. The framework's own
telemetry — use-case spans, emissions, lifecycle, bindings, errors — now
arrives as one typed `JuiceTelemetry` object per entry instead of a message
plus a context map. The free-form `log` and `logError` stay for your own
lines.

```dart
// the smallest complete migration: forward telemetry to your existing path
@override
void record(JuiceTelemetry e) => e.isError
    ? logError(e.message, e.error!, e.stackTrace ?? StackTrace.empty,
        context: e.toMap())
    : log(e.message, level: e.level, context: e.toMap());
```

`e.toMap()` is the 1.x context map (the same `type`, `action` and field
keys, `streamBindings` and `blocsEnded` included; values live). The
`message` is a constant per kind — the status, reason or callback that
used to be interpolated into it is a field. A thrown use-case error is two
entries — `useCaseFailed` (the span's close, with `executionId`) and
`blocError` — where 1.x logged three lines; a bloc's close is one
`bloc_lifecycle` · `close` entry (the scope no longer logs its own beside
it); a sequential run's escaped failure is its own `type`
(`sequential_run_error`), as is a failed supersede (`supersede_error`); the
retry kinds (`retry_scheduled`, `retry_exhausted`, `retry_abandoned`) carry
`attempt`, `bloc` and a live `error`, and the 1.x free-form retry lines'
`maxRetries`, `delayMs` and `totalAttempts` keys are gone; the framework's
other free-form lines (the dispatcher's fallback warning, `get` on a leased
bloc, the error handler's debug prints) are kinds or gone. The whole
vocabulary, with levels, fields and what changed on the wire:
`packages/juice/doc/TELEMETRY.md` §3 and §6.

`DevtoolsJuiceLogger` (`juice_observability` 0.6.0, in the wave) implements
`record` and posts the same payload shape as before, plus the new kinds.

### Dead surface removed

`JuiceBloc.logger`, `JuiceAsyncBuilder.waiting`, `denyRebuild`'s `key`
parameter, and `RelayUseCaseBuilder`. Drop the calls and arguments; nothing
observable changes. `RelayUseCaseBuilder` becomes a `StateRelay` or
`StatusRelay` (`doc/concepts/relay-use-cases.md`). Internal members that
were never exported are gone too (`UseCaseContext.getState` / `getOldState`
/ `navigateAsync`, `AviatorManager.navigateAsync` / `hasAviator` /
`aviatorCount` / `aviatorNames`, `UseCaseRegistry.builderCount`,
`EventDispatcher.handlerCount`); no program outside the package could
reach them.

## Behaviour changes

### Relays and subscriptions initialise synchronously, and throw

`StateRelay`, `StatusRelay` and `EventSubscription` resolve their blocs in
the constructor and throw when a bloc is unregistered or closed — where the
developer is looking, not as an uncaught error from a microtask. The error
is the resolver's own: a `StateError` from `BlocScope`; a custom
`resolver:`'s error passes through unchanged, where 1.x wrapped it in a
`StateError('StateRelay initialization failed: …')`. A failed
initialisation holds no lease. `EventSubscription.initialize()` on a closed
subscription throws `StateError`; 1.x did nothing.

Two consequences:

- Register both blocs before constructing a relay.
- **Never build a relay, or lease a bloc, inside a bloc's own
  constructor.** A bloc leased while its own factory is running fails at
  the scope with `StateError`. Wire relays in the composition root:

```dart
// 1.x — worked only because the relay initialised a microtask later
class SettingsBloc extends JuiceBloc<SettingsState> {
  SettingsBloc() : super(…) {
    _relay = StateRelay<SettingsBloc, NotesBloc, SettingsState>(toEvent: …);
  }
}

// 2.0 — main.dart, after the registrations
BlocScope.register<SettingsBloc>(() => SettingsBloc(), lifecycle: BlocLifecycle.permanent);
BlocScope.register<NotesBloc>(() => NotesBloc(), lifecycle: BlocLifecycle.permanent);
StateRelay<SettingsBloc, NotesBloc, SettingsState>(toEvent: …);
```

An `EventSubscription` in a builder list leases its source from the
subscribing bloc's constructor; two blocs that subscribe to each other
cannot be constructed — subscribe one way.

### `sendAndWait` fails loud

`sendAndWait` returns the terminal status emitted for THAT event. It now
fails with `StateError` the moment processing ends with no terminal status
— the event was dropped by a `droppable` builder, no use case handles it,
the use case emitted nothing, or the bloc closed during the wait — instead
of waiting out the timeout. On a closed or closing bloc the returned future
fails (the call no longer throws). `sendAndWaitResult`, `sendForResult` and
`BlocTester.sendAndWaitForResult` are built on it; the tester now answers
for that event rather than the first non-waiting status of any event, and
`sendAndWaitResult` fails the event's `result` on every failure of the wait
(closed bloc, no handler, nothing emitted, timeout, close mid-wait), where
1.x failed it only for a missing terminal status.

A test that relied on the timeout gets the error at once; a use case that
is expected to emit nothing is awaited with `send`, not `sendAndWait`.

### `StatefulUseCaseBuilder` cannot be `restartable`

One instance serves every run and cannot be fenced per run: registering
the pair throws `ArgumentError`. Use `UseCaseBuilder`, or another mode.

### An emit adopts the caller's group set

The first emit for an event stores the set the use case passed (no copy);
a later emit for the same event merges into a new set. Do not mutate a
group set after passing it.

### Widgets keep their subscription across parent rebuilds

Every widget form keys its bloc subscription on the bloc instances
(`SubscriptionKey`, new) and applies the rebuild groups and
`onStateChange` live through `JuiceAsyncBuilder`'s new `where`, from the
current widget. A parent rebuild no longer cancels and re-listens. Listen
order is therefore stable across rebuilds; code that depended on a
re-listen per build (none was documented) needs a key change to force one.

### Telemetry below the floor is not built

Every info-level entry — the use-case span, emissions, lifecycle, leases,
bindings, retries, subscriptions — is built only when
`JuiceLoggerConfig.logs(level)` keeps it. Recorded whatever the floor says:
the error kinds, `emissionAfterClose`, `eventIgnored`, `leasedBlocGot`,
`streamBindingRefused` and a failure emission. In 1.x the lifecycle and
lease entries bypassed the floor.

### Smaller changes

- `sendCancellable` always goes through `send`; a refusal on a closed bloc
  is logged (`eventIgnored`, warning), never silent.
- A Juice widget's `error:` builder receives the builder's own
  `BuildContext`, not the `State`'s outer one.
- `RetryableUseCaseBuilder` stops before `onRetry` and the backoff once its
  run is superseded.
- `LocationBloc` (`juice_location` 0.3.0): close closes the bloc, then
  disposes the source; a positions stream that errors or ends sets
  `tracking: false` (`TrackingEndedEvent`); `source` before initialisation
  throws a named `StateError`.
- `LlmBloc` (`juice_llm` 0.6.0): close stops the generation first, refuses
  generations once closing, disposes the provider once; `config` before
  initialisation throws a named `StateError`.

## New in 2.0

- **`EventConcurrency.restartable`** — latest input wins. A same-type event
  arriving while one runs supersedes it; the superseded run is fenced
  (every emit and navigation dropped, its stream bindings cancelled, its
  `CancellableEvent` cancelled), `BlocUseCase.isSuperseded` is the check for
  any other event (`JuiceBloc.isSuperseded(event)` from outside a use case),
  and `sendAndWait` on it answers `CancelingStatus`. Side effects already
  performed are not rolled back.
- **`JuiceBloc.bindStream` / `unbind` / `StreamBinding`** — the bloc owns
  every stream it listens to: cancelled at the start of `close()`, keyed
  for idempotent starts, errors routed to the bloc's error handler. No
  `StreamSubscription` field, no `isClosed` guard, no manual cancel.
  `StreamBinding` exposes `key`, `isActive`, `done` and `cancel()`;
  `JuiceBloc.activeBindingCount` counts the live bindings.
- **`JuiceBloc.seedState(state, {groups})`** — the `@visibleForTesting`
  seam `juiceTest(seed:)` uses.
- **`JuiceTelemetry`, `JuiceTelemetryKind`, `EmissionKind`** — the typed
  telemetry vocabulary (`packages/juice/doc/TELEMETRY.md`).
- **`JuiceAsyncBuilder.streamKey` and `where`.**
- **Performance** — on the benchmark Mac a send is 0.66 µs with the
  telemetry chatter on and 0.44 µs with it off (the release default), from
  2.83 and 1.95 on the 2.0 tree before the performance work (1.10.0 had
  measured 2.72 and 1.82 on the same bloc). Against bloc and Riverpod
  (`benchmarks/RESULTS.md` §16–§17): the sequential release-default
  dispatch is under bloc's on the Mac and the phone (0.73 / 0.63 µs vs
  1.04 / 1.03), ties bloc with every telemetry record built, trails bloc
  in the burst shape, and sits above Riverpod's synchronous notifier (0.42
  / 0.41), which has no event queue to pay for; per frame the tuned Juice
  and Riverpod forms tie and bloc's BlocSelector trails them.

## Checklist

1. Add `concurrency:` to every builder (the compiler lists them); add the
   `restartable` case to any exhaustive `switch` over `EventConcurrency`;
   no `StatefulUseCaseBuilder` may be `restartable`.
2. Replace `UpdateEvent(newState:)` with a real event; drop `<TState>`.
3. Replace `GlobalBlocResolver` with `BlocScope.register`. A tenant,
   feature-flag or environment resolver has no global slot to sit in any
   more: pass it to the widgets and relays that take `resolver:`, or make
   the choice inside the factories you register.
4. Replace each `RelayUseCaseBuilder` with a `StateRelay` or `StatusRelay`
   by hand (`doc/concepts/relay-use-cases.md`); drop the removed members
   the compiler names.
5. Add `record` to every `JuiceLogger` implementation (the forwarding
   one-liner above is enough).
6. Move any relay built inside a bloc constructor to the composition root.
7. Do not mutate a group set after passing it to an emit.
8. Run the tests: a `sendAndWait` that used to time out now throws at once,
   and `juiceTest` now fails on an unexpected stream-binding error
   (`errors:` to expect one).
9. Bump the family packages to the versions below, together.

## The family wave

Every published package below requires `juice: ^2.0.0`, except the two
footnoted. A 0.x package takes a minor bump, a 1.x+ package a major one
(`juice_routing` 2.0.0, `juice_storage` 3.0.0); the packages that depend on
`juice_storage` accept it up to `<4.0.0`. The packages marked *changed*
carry code of their own in the wave; the rest are constraint bumps with no
API change.

| Package | at juice 1.10.0 | 2.0 wave | |
|---|---|---|---|
| juice_analytics | 0.2.0 | 0.3.0 | |
| juice_auth | 0.3.0 | 0.4.0 | |
| juice_auth_network | 0.1.3 | 0.2.0 | requires `juice_auth ^0.4.0`, `juice_network ^0.14.0` |
| juice_auth_routing | 0.1.2 | 0.2.0 | requires `juice_auth ^0.4.0`, `juice_routing ^2.0.0` |
| juice_connectivity | 0.2.0 | 0.3.0 | *changed*: bloc-owned `changes` binding, close order, loud dispose; `connectivity_plus` up to 7 |
| juice_flags | 0.2.0 | 0.3.0 | |
| juice_forms | 0.3.0 | 0.4.0 | |
| juice_i18n | 0.2.0 | 0.3.0 | |
| juice_lifecycle | 0.2.0 | 0.3.0 | *changed*: as connectivity |
| juice_lint | 0.2.0 | 0.3.0 | *changed*: `juice_missing_concurrency_mode` retired (analyzer plugin: no `juice` dependency; not yet on pub.dev) |
| juice_llm | 0.5.0 | 0.6.0 | *changed*: bloc-owned generation binding, close order |
| juice_llm_llamacpp | 0.2.3 | 0.2.3 | unchanged (depends on `juice_llm`, not on `juice`; not republished) |
| juice_location | 0.2.0 | 0.3.0 | *changed*: bloc-owned tracking binding, `TrackingEndedEvent`; `geolocator` up to 14 |
| juice_media | 0.6.0 | 0.7.0 | *changed*: per-upload progress bindings, close order, loud dispose |
| juice_network | 0.13.1 | 0.14.0 | |
| juice_notifications | 0.2.0 | 0.3.0 | *changed*: bloc-owned `taps` binding, close order, loud dispose; `flutter_local_notifications` 20–22 (named-parameter API; Flutter ≥ 3.32) |
| juice_observability | 0.5.1 | 0.6.0 | *changed*: `DevtoolsJuiceLogger.record` |
| juice_paging | 0.2.0 | 0.3.0 | |
| juice_permissions | 0.3.0 | 0.4.0 | `permission_handler` up to 13 |
| juice_power | 0.1.0 | 0.2.0 | *changed*: as connectivity; `battery_plus` up to 7 |
| juice_realtime | 0.2.0 | 0.3.0 | *changed*: bloc-owned `messages` binding, socket error = connection loss, close order |
| juice_routing | 1.3.0 | 2.0.0 | |
| juice_storage | 2.3.0 | 3.0.0 | `flutter_secure_storage` up to 11 |
| juice_sync | 0.2.1 | 0.3.0 | |
| juice_theme | 0.2.0 | 0.3.0 | |

What *changed* means for the seven stream-owning blocs (connectivity,
lifecycle, location, media, notifications, power, realtime): each bloc's
provider stream is a `bindStream` binding the bloc cancels at the start of
`close()`, before the use cases close; `close()` then disposes the
provider, logging (never swallowing) a dispose failure; a provider stream
error reaches the bloc's error handler and ends the binding instead of
escaping as an uncaught error; and reading the provider before the
initialize event throws a named `StateError`. Each package's CHANGELOG
has the exact list.
