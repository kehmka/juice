# Juice — AI Agent Guide

This file orients an AI model to the **Juice** Flutter state-management framework
and its package family. Juice is not widely represented in training data, so read
this in full before writing or modifying Juice code. The **Gotchas** section near
the end lists the mistakes AI models reliably make — check it before you emit code.

> Human docs live in `doc/` (a site) and each package's `doc/SPEC.md`. This file
> is the dense, AI-targeted mental model. Per-package AI references live at
> `packages/<pkg>/doc/LLM.md`.

---

## 1. Mental model (one screen)

Juice is **event-in / state-out**, with logic isolated in **use cases**:

```
UI ──event──▶ Bloc ──dispatch──▶ UseCase ──emit(newState, groups)──▶ Bloc.state ──▶ Widgets rebuild (by group)
```

- **`JuiceBloc<TState>`** — holds immutable `TState`; registers one use case per
  event type. Never put business logic in the bloc body beyond small helpers and
  resource lifecycle.
- **`EventBase`** — an event is a plain data object. Sent with `bloc.send(event)`.
- **`BlocUseCase<TBloc, TEvent>`** — one class per event. Its `execute(event)`
  reads `bloc.state`, does work, and calls `emitUpdate`/`emitFailure`. **This is
  where all logic lives.**
- **`BlocState`** — immutable; every change goes through `copyWith`.
- **Rebuild groups** — named strings. A widget rebuilds only when an emitted
  group set **intersects** the widget's group set (so rebuilds are selective).
- **`StatelessJuiceWidget<TBloc>`** — a widget bound to a bloc + a set of groups;
  its `bloc` getter resolves from the scope.
- **Seam** — anything touching a vendor/SDK/platform is behind an injected
  interface (the "seam"), with a shipped default impl and a fake for tests. The
  bloc never imports a vendor SDK directly.

---

## 2. Canonical package shape

Every package in this family follows the same skeleton. Once you know one, you
know all of them. A package `juice_foo` owning domain "foo" looks like:

```dart
// foo_state.dart
abstract final class FooGroups {                 // rebuild groups (named intents)
  static const status = 'foo:status';
  static String item(String id) => 'foo:item:$id'; // dynamic per-id group
  static const all = {status};
}

class FooState extends BlocState {
  final List<Item> items;
  final String? error;
  const FooState({this.items = const [], this.error});
  static const initial = FooState();
  FooState copyWith({List<Item>? items, Object? error = _unset}) => FooState(
        items: items ?? this.items,
        error: identical(error, _unset) ? this.error : error as String?,  // nullable: sentinel
      );
}
const Object _unset = Object();

// foo_source.dart — the SEAM (+ a default impl + a fake live in tests)
abstract class FooSource { Future<List<Item>> load(); Future<void> dispose(); }

// foo_config.dart
class FooConfig { final FooSource source; FooConfig({FooSource? source}) : source = source ?? DefaultFooSource(); }

// foo_events.dart
abstract class FooEvent extends EventBase { @override String toString() => runtimeType.toString(); }
class InitializeFooEvent extends FooEvent { final FooConfig config; InitializeFooEvent({required this.config}); }
class LoadFooEvent extends FooEvent {}

// foo_bloc.dart
class FooBloc extends JuiceBloc<FooState> {
  late FooConfig _config;
  FooBloc() : super(FooState.initial, [
    () => UseCaseBuilder(typeOfEvent: InitializeFooEvent, useCaseGenerator: () => InitializeFooUseCase(), concurrency: EventConcurrency.droppable),
    () => UseCaseBuilder(typeOfEvent: LoadFooEvent,       useCaseGenerator: () => LoadFooUseCase(), concurrency: EventConcurrency.droppable),
  ]);
  factory FooBloc.withConfig(FooConfig config) {           // standard construction
    final b = FooBloc();
    b.send(InitializeFooEvent(config: config));            // init use case applies config
    return b;
  }
  void configure(FooConfig c) => _config = c;
  FooSource get source => _config.source;
  void load() => send(LoadFooEvent());                     // thin convenience wrappers
  @override Future<void> close() async { await _config.source.dispose(); await super.close(); }
}

// use_cases/load_foo_use_case.dart
class LoadFooUseCase extends BlocUseCase<FooBloc, LoadFooEvent> {
  @override Future<void> execute(LoadFooEvent event) async {
    try {
      final items = await bloc.source.load();
      emitUpdate(newState: bloc.state.copyWith(items: items), groupsToRebuild: {FooGroups.status});
    } catch (e) {
      emitFailure(newState: bloc.state.copyWith(error: e.toString()), groupsToRebuild: {FooGroups.status}, error: e);
    }
  }
}
```

`lib/juice_foo.dart` is a barrel that exports `src/*` (and the default provider).

**Type-checked registration (juice ≥ 1.9.0).** `UseCaseBuilder.typed(() =>
LoadFooUseCase(), concurrency: EventConcurrency.droppable)` infers the event type from the use case — pairing
`typeOfEvent: SaveEvent` with a `LoadUseCase` becomes a compile error instead
of a dispatch-time cast failure — and checks the use case's bloc type when the
bloc registers it (wrong bloc → `ArgumentError` from the constructor). Takes
`concurrency:` and `initialEventBuilder:` like the constructor. Prefer it in
new code; keep the explicit constructor only for a use case declared over an
abstract base event (events match by exact runtime type, gotcha 2).

**Events that return a value (juice ≥ 1.9.0).** Extend `ResultEvent<T>`. The
use case emits a terminal status for that event (`emitUpdate` on success,
`emitFailure` / `emitCancel` otherwise) and calls `event.succeed(value)`;
callers `await bloc.sendForResult(event)` (value, or throws the failure's
error) or `bloc.sendAndWaitResult(event)` (an `OperationResult` with the
status too). A dropped event or a use case that emits nothing fails loud
instead of timing out. Don't hand-roll a `Completer` field on an event.

---

## 3. Widgets

```dart
class FooList extends StatelessJuiceWidget<FooBloc> {
  FooList({super.key}) : super(groups: {FooGroups.status});   // rebuilds only on this group
  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    return Text('${bloc.state.items.length}');                 // `bloc` resolves from scope
  }
}
```

Register + resolve via the scope:

```dart
BlocScope.register<FooBloc>(() => FooBloc.withConfig(FooConfig()), lifecycle: BlocLifecycle.permanent);
final foo = BlocScope.get<FooBloc>();    // imperative access outside a widget
// lifecycles: BlocLifecycle.permanent | feature | leased (use BlocScope.lease for leased)
```

A widget's bloc subscription is kept across parent rebuilds (keyed on the
bloc instances); its groups and `onStateChange` are read from the CURRENT
widget on every emission.

**Hot cells: `JuiceSelector` inside groups.** Groups remain
the invalidation vocabulary — cross-widget, intent-named. For a LEAF that
rebuilds too often inside a group's blast radius (one field of a list row,
a ticker), select it: `JuiceSelector<FooBloc, FooState, int>(groups:
{FooGroups.status}, selector: (s) => s.count, builder: …)` rebuilds only when
an emission targets `status` AND `count` changed by `==`. Always pass
`groups` — without them every emission is projected and the invalidation is
unnamed. The selected type needs VALUE equality (same precondition as
`skipIfSame`); for collections use `JuiceSelectorWith(equals: listEquals)`.
The stream forms `bloc.select` / `selectWith` take the same `groups`. Not a
dependency graph: nothing is auto-tracked, and a rebuild is still explained
by two constants plus one comparison.

**Per-item async state.** `StreamStatus` is bloc-wide — it can't say "row 7 is
loading while the rest are fine." For a *collection* whose items each have their
own async life (a row uploading, deleting, retrying), do **not** reach for a
hand-rolled `Set<busyId>` (no failure surface; leak-prone). Hold an
`EntityStatuses<K>` in your state and drive it with `BlocUseCase.guardEntity`
(sets waiting → idle, or failure on throw — cleanup guaranteed); read it with
`state.field.statusOf(key).when(idle: …, waiting: …, failure: …)`. Guide:
[packages/juice/doc/ENTITY_STATUS_GUIDE.md](packages/juice/doc/ENTITY_STATUS_GUIDE.md)
· spec: [packages/juice/doc/ENTITY_STATUS_SPEC.md](packages/juice/doc/ENTITY_STATUS_SPEC.md).

---

## 4. Concurrency (critical)

Every builder DECLARES how same-type events interleave — `concurrency:` is
required; a mode is a decision, never a default. Under `concurrent`, when an
`execute()` suspends at an `await`, another event's use case of the same type
can run during that suspension. Pick the mode per event — this is the
primary fix, not a hand-rolled guard:

```dart
() => UseCaseBuilder(
  typeOfEvent: SaveEvent,
  useCaseGenerator: () => SaveUseCase(),
  concurrency: EventConcurrency.sequential,   // required: .sequential, .droppable, .restartable or .concurrent
),
```

- **`sequential`** — for events that **mutate shared state** (a list/map, a
  counter). Same-type events queue and run one-at-a-time to completion; the
  read-before-await race is impossible.
- **`droppable`** — for **exclusive flows** (flush, connect, pick): a same-type
  event arriving while one runs is ignored. Replaces a manual `if (_busy) return`.
- **`restartable`** — for **latest-input-wins** (search,
  filter, select, load-by-id, scrubbing): a same-type event arriving while
  one runs SUPERSEDES it and starts at once. Dart cannot kill the old run, so
  it is fenced: every emission and navigation it attempts afterwards is
  dropped (logged `state_emission_superseded`), the stream bindings it
  created are cancelled, and if its event is a `CancellableEvent` that is
  cancelled too. Long loops check `isSuperseded` (on `BlocUseCase`, correct
  after any await) or `event.isCancelled` and return. `sendAndWait` on a
  superseded event answers with a `CancelingStatus` instead of timing out.
  **Side effects already performed are NOT rolled back** — restartable
  fences state, not the world. Gotchas: a run that has RETURNED is not in
  flight (to tie a stream binding's life to the run, `await binding.done`,
  or give it a `key`, which replaces regardless of mode); a `send` made from
  inside the run is its OWN run (not fenced with the outer one), while a
  Timer / Future.delayed / listener the run created IS the run; an event
  instance is single-use — re-sending the same instance is a new run that
  supersedes the old, and `sendAndWait` / `bloc.isSuperseded(event)` then
  answer for the latest run. `StatefulUseCaseBuilder` cannot be restartable
  (one instance cannot be fenced per run; refused at registration).
- **`concurrent`** — for **genuinely independent** events.

**Waiting on an event.** `sendAndWait(event)` returns the terminal status
emitted FOR THAT EVENT. It fails loud (`StateError`) the moment processing
ends with no terminal status — dropped by `droppable`, no use case, a use
case that emitted nothing, a close mid-wait — instead of waiting out the
timeout. `sendAndWaitResult` / `sendForResult` (typed `ResultEvent`s) and
`BlocTester.sendAndWaitForResult` are built on it.

When you *do* stay `concurrent`, follow the discipline:

- ✅ **Read `bloc.state` at emit time (after any await), never a snapshot taken
  before the await.** A synchronous read-modify-write — `bloc.state.copyWith(...
  bloc.state.x ...)` with no `await` between the read and the emit — is atomic
  (`emitUpdate` sets `bloc.state` synchronously).
- ❌ **Bug pattern:** `final snap = bloc.state.list; await x(); emit(... mutate(snap) ...)`
  → another event mutated the list during `await x()`; you just clobbered it.
  Either switch the event to `sequential`, or read `bloc.state.list` *after* the
  await.

---

## 4b. Streams a bloc listens to

A bloc never holds a `StreamSubscription` field. It binds:
`bindStream<T>(stream, (item) => send(ItemEvent(item)), key: 'tracking')`
from a use case or a bloc helper; the bloc owns the binding — cancelled at
the start of `close()` before the use cases close, `onData` never runs while
closing, no `isClosed` guard, no manual cancel in `close()`. `key` makes
start idempotent (a re-bind replaces) and `unbind(key)` is stop; an
anonymous binding stops through `StreamBinding.cancel()` (returns the
subscription's own cancel future — bound it if a provider's teardown can
wedge). Errors are loud: no `onError` → the bloc's error handler, and the
binding is cancelled unless `cancelOnError: false`; an `onData` that throws
→ error handler, binding stays; an `onError` / `onDone` that throws → error
handler too (`stream_binding`/`callback_error`). A bind on a closing bloc or
from a superseded restartable run is refused: an inert binding, logged
`stream_binding`/`refused` with its `reason`. Gotcha: `onData` is for turning
items into EVENTS — emit from the use case the event dispatches, not from
`onData`.

## 4c. Telemetry

The framework reports through `JuiceLogger.record(JuiceTelemetry entry)`:
one typed object per entry, a closed vocabulary (`JuiceTelemetryKind`),
values live (the emitted state, the caller's group set), nothing
stringified until a logger prints or ships it. The use-case span is two
entries sharing an `executionId` — `useCaseStarted`, then `useCaseCompleted`
(with `elapsedMicros`) or `useCaseFailed`; every emission is `stateEmitted`;
lifecycle, bindings and errors have their kinds. Free-form lines (yours:
`BlocUseCase.log` / `logState` / `logError`) still go through `log` /
`logError` with a context map. The reference, every kind with its level and
fields: `packages/juice/doc/TELEMETRY.md`.

Cost follows the consumer: the framework builds an entry only if
`JuiceLoggerConfig.logs(level)` says it is kept — the global floor
`JuiceLoggerConfig.minLevel` AND the configured logger's own declaration
(`LevelAwareJuiceLogger.minLevel`). `DefaultJuiceLogger` declares everything
in debug and nothing in profile/release; `DevtoolsJuiceLogger`
(`juice_observability`) declares everything while a listener is attached. A
custom logger that only `implements JuiceLogger` keeps everything —
implement the interface, or set the floor. Never gated: every error kind,
`emissionAfterClose`, `eventIgnored`, `leasedBlocGot`, `streamBindingRefused`,
a failure emission; everything else, lifecycle and leases included, is built
only when the floor keeps it.

A thrown use-case error is two entries: `useCaseFailed` (the span's close)
and `blocError` (the bloc's `onError` hook). Span consumers key on the
first, error counters on the second. Mirror everything to DevTools with
`JuiceLoggerConfig.configureLogger(DevtoolsJuiceLogger())`.

A custom logger's smallest complete `record` forwards to its own free-form
path: `e.isError ? logError(e.message, e.error!, e.stackTrace ??
StackTrace.empty, context: e.toMap()) : log(e.message, level: e.level,
context: e.toMap())`.

## 4d. Skipping duplicate emits (`skipIfSame`)

`emitUpdate(newState: …, groupsToRebuild: …, skipIfSame: true)` suppresses
the emission when `newState == state`, logging `state_emission_skipped`
instead of rebuilding. Two rules:

- **It is PER-CALL, never a bloc-wide mode.** Turn it on at a specific
  emission site where a no-op refresh is possible (re-fetch that often
  returns identical data). A blanket mode would swallow intentional
  re-emits — e.g. a `waiting → waiting` refresh, or re-emitting an equal
  state to replay a transient. Only `emitUpdate` has it; `emitWaiting`/
  `emitFailure`/`emitCancel` deliberately do not.
- **It requires VALUE EQUALITY on the state.** With only identity `==`,
  `newState == state` is always false and nothing is ever skipped. Give
  the state (or the changed field's type) real `==`/`hashCode` —
  `EntityStatuses` and the framework value types already have it.

> Many of these gotchas are now enforced by **`juice_lint`** (an
> `analysis_server_plugin` analyzer plugin, reported by `dart analyze` and
> the IDE — not by Flutter 3.47's `flutter analyze`, which exits before
> plugin results arrive): `juice_generic_event`,
> `juice_mutable_state_field`, `juice_behavior_in_state`,
> `juice_send_in_build`, `juice_lease_in_build`,
> `juice_stale_read_across_await`. (The opt-in
> `juice_missing_concurrency_mode` was retired in 2.0: `concurrency:` is a
> required parameter, so the compiler enforces it.) Enable the plugin with a
> top-level `plugins: juice_lint:` section in `analysis_options.yaml` (no
> pubspec dependency); suppress one site with `// ignore: juice_lint/<rule>`.

## 5. Gotchas — what AI models get wrong about Juice

1. **`StatelessJuiceWidget` subclasses CANNOT be `const`.** `const MyWidget()`
   where `MyWidget extends StatelessJuiceWidget` is a compile error
   (`const_constructor_with_non_const_super`). Never put `const` on them, nor on
   a parent (`PreferredSize`, a `Column`'s child list) that forces it.
2. **Events are matched by exact runtime type.** A **generic** event
   (`InitEvent<T>`) won't match a `typeOfEvent: InitEvent` builder. Keep events
   non-generic; pass typed config via the `withConfig` factory, not a generic
   event.
3. **Apply the concurrency rule (section 4).** Read-before-await-then-write-stale
   is the #1 latent bug.
4. **Rebuild groups accumulate on a single multi-emit event.** Within ONE event's
   use case that emits many times (e.g. a flush loop), the groups accumulate on
   that event object — so per-id targeting coalesces *within that burst*. Across
   separate events, targeting is clean.
5. **State holds data, not behavior.** Validators, callbacks, timers, vendor
   handles live on the bloc/config, never in `BlocState` (state must stay an
   immutable value).
6. **`copyWith` for a nullable field needs an `_unset` sentinel** (see section 2)
   — a plain `x ?? this.x` can't distinguish "not passed" from "set to null", so
   the field becomes unclearable.
7. **Seam, not vendor import.** To support Firebase/Sentry/Dio/etc., implement
   the package's seam interface in the app; do NOT add the vendor dep to the
   feature bloc. Ship a default impl + a fake.
8. **`close()` releases what the bloc created** — timers, seams — before
   `super.close()`; streams bound with `bindStream` are cancelled for you at
   the start of close. You do NOT need to guard emits against a closed bloc:
   an in-flight use case's emit after close is dropped and logged
   (`emission_after_close`), and events sent once `close()` starts are refused
   (`bloc.isClosing`).
9. **Fail loud.** Missing/invalid input → `emitFailure` or throw with a reason;
   never silently fall back to a default. Multi-sink blocs isolate each sink
   (try/catch per sink) so one failure can't break the rest.

10. **Builders register once, at construction — a NEW `UseCaseBuilder` needs a
   hot RESTART.** Hot reload keeps the live bloc instance, whose dispatcher
   table was filled in its constructor; a builder added to the list (or a
   changed `typeOfEvent`) is not registered until the bloc is constructed
   again. Edits INSIDE a use case hot-reload fine (the generator builds a
   fresh instance per event). If an event suddenly reports "No handler
   registered", restart before debugging.

11. **Never build a relay, or lease a bloc, inside a bloc's own constructor.**
   `StateRelay` / `StatusRelay` / `EventSubscription` resolve their blocs
   synchronously; a bloc that leases ITSELF while its factory runs fails at
   the scope with a `StateError`. Wire relays in the composition root, after
   the registrations. An `EventSubscription` in a builder list leases its
   SOURCE from the constructor — fine, unless two blocs subscribe to each
   other.

---

## 6. Build & test

```bash
dart run melos bootstrap          # wire the monorepo (run after adding a package/dep)
cd packages/juice_foo
flutter analyze                   # must be clean (0 issues)
flutter test                      # headless bloc tests (fake the seam)
flutter pub publish --dry-run     # 0 warnings expected (a pubspec_overrides hint is normal)
```

Tests are headless: implement a fake of the seam, drive the bloc, assert on
what it emitted. Prefer **`juiceTest`** (`package:juice/testing.dart`) over
sleeping:

```dart
juiceTest<FooBloc, FooState>(
  'load emits the items on the status group',
  build: () => FooBloc(),
  act: (b) async {
    await b.send(InitializeFooEvent(config: FooConfig(source: FakeFooSource())));
    await b.send(LoadFooEvent());              // send() completes when processed
  },
  skip: 1,                                     // the init emission
  expect: () => [isUpdatingStatus(groups: {FooGroups.status})],
);
```

`act` returns the `send()` futures (no `settle()`), the bloc is closed before
asserting, each emission's groups are snapshotted at emit time (gotcha 4), an
unexpected use-case or stream-binding error fails the test (`errors:` to
expect them), and a use
case still running at close fails it. `wait:` is only for deliberate timers or
debounces. Construct with the plain constructor and send the init event in
`act` — `withConfig` fires it without returning the future.

Examples are **juice-pure**: only the juice family + flutter; a `Demo*` seam impl
so the app runs with no device/backend; a trivial smoke test.

---

## 7. Naming & conventions

- Blocs `FooBloc`, state `FooState`, events `VerbNounEvent`, use cases
  `VerbNounUseCase`, groups `abstract final class FooGroups`.
- Imports: `import 'package:juice/juice.dart';` (it re-exports flutter +
  dart:async; importing those separately makes analyze flag an unnecessary import).
- Document public APIs with `///`. Errors via `emitFailure`. Always implement
  `close()`.

---

## 8. The package family

See `ROADMAP.md` for the full catalog, the locked architectural decisions, the
versioning/maturity ladder, and the concurrency-semantics section. Substrate:
`juice`, `juice_storage`, `juice_routing`. Everything else is a domain bloc, an
ambient signal, a presentation service, or a glue package — all following the
shape above.
