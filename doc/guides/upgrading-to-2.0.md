---
layout: default
title: Upgrading to 2.0
parent: Guides
nav_order: 99
---

# Upgrading to juice 2.0.0

2.0.0 is the breaking set, shipped together. This guide lists every change
that can stop a 1.x program compiling or alter what it does, with the
migration for each, then the new surface. The CHANGELOG has the same list
in release-note form; `benchmarks/RESULTS.md` §15 has the numbers.

Every family package has a matching major or minor bump that requires
`juice: ^2.0.0`; upgrade them together.

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

`e.toMap()` is the 1.x context map (same `type`, `action` and field keys;
values live). Two keys were renamed: the bloc close entry's
`streamBindings` and the feature scope's `blocsEnded` are both `count`. A
thrown use-case error is two entries — `useCaseFailed` (the span's close,
with `executionId`) and `blocError` — where 1.x logged three lines. The
whole vocabulary, with levels and fields: `packages/juice/doc/TELEMETRY.md`.

`DevtoolsJuiceLogger` (`juice_observability` 0.6.0) implements `record`;
its wire format is unchanged.

### Dead surface removed

`UseCaseContext.getState` / `getOldState` / `navigateAsync`,
`JuiceBloc.logger`, `JuiceAsyncBuilder.waiting`, `AviatorManager.navigateAsync` /
`hasAviator` / `aviatorCount` / `aviatorNames`, `UseCaseRegistry.builderCount`,
`EventDispatcher.handlerCount`, `denyRebuild`'s `key` parameter, and
`RelayUseCaseBuilder`. Drop the calls and arguments; nothing observable
changes. `RelayUseCaseBuilder` becomes a `StateRelay` or `StatusRelay`
(`doc/concepts/relay-use-cases.md`).

`SubscriptionKey` (a `JuiceAsyncBuilder` key the widget forms use) takes
the bloc list only; `JuiceAsyncBuilder` has a new `where`.

## Behaviour changes

### Relays and subscriptions initialise synchronously, and throw

`StateRelay`, `StatusRelay` and `EventSubscription` resolve their blocs in
the constructor and throw `StateError` when a bloc is unregistered or
closed — where the developer is looking, not as an uncaught error from a
microtask. A failed initialisation holds no lease.

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
for that event rather than the first non-waiting status of any event.

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

Every widget form keys its bloc subscription on the bloc instances and
applies the rebuild groups and `onStateChange` live, from the current
widget. A parent rebuild no longer cancels and re-listens. Listen order is
therefore stable across rebuilds; code that depended on a re-listen per
build (none was documented) needs a key change to force one.

### Smaller changes

- `sendCancellable` always goes through `send`; a refusal on a closed bloc
  is logged (`eventIgnored`, warning), never silent.
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
  any other event, and `sendAndWait` on it answers `CancelingStatus`. Side
  effects already performed are not rolled back.
- **`JuiceBloc.bindStream` / `unbind` / `StreamBinding`** — the bloc owns
  every stream it listens to: cancelled at the start of `close()`, keyed
  for idempotent starts, errors routed to the bloc's error handler. No
  `StreamSubscription` field, no `isClosed` guard, no manual cancel.
- **`JuiceBloc.seedState(state, {groups})`** — the `@visibleForTesting`
  seam `juiceTest(seed:)` uses.
- **`JuiceTelemetry` / `JuiceTelemetryKind`** — the typed telemetry
  vocabulary (`packages/juice/doc/TELEMETRY.md`).
- **`JuiceAsyncBuilder.streamKey` and `where`.**
- **Performance** — a send is 0.67 µs with the telemetry chatter on and
  0.44 µs with it off (the release default), from 2.8 and 2.0 in 1.10.0 on
  the same machine; `benchmarks/RESULTS.md` §15.

## Checklist

1. Add `concurrency:` to every builder (the compiler lists them).
2. Replace `UpdateEvent(newState:)` with a real event; drop `<TState>`.
3. Replace `GlobalBlocResolver` with `BlocScope.register`.
4. Add `record` to every `JuiceLogger` implementation (the forwarding
   one-liner above is enough).
5. Move any relay built inside a bloc constructor to the composition root.
6. Run the tests: a `sendAndWait` that used to time out now throws at once.
7. Bump the family packages to their 2.0-compatible versions.
