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
    () => UseCaseBuilder(typeOfEvent: InitializeFooEvent, useCaseGenerator: () => InitializeFooUseCase()),
    () => UseCaseBuilder(typeOfEvent: LoadFooEvent,       useCaseGenerator: () => LoadFooUseCase()),
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

---

## 4. Concurrency (critical)

By default Juice runs same-type use cases **`concurrent`**ly: when an `execute()`
suspends at an `await`, another event's use case of the same type can run during
that suspension. Pick the right **concurrency mode** per event on its
`UseCaseBuilder` (juice ≥ 1.5.0) — this is the primary fix, not a hand-rolled
guard:

```dart
() => UseCaseBuilder(
  typeOfEvent: SaveEvent,
  useCaseGenerator: () => SaveUseCase(),
  concurrency: EventConcurrency.sequential,   // or .droppable, or .concurrent (default)
),
```

- **`sequential`** — for events that **mutate shared state** (a list/map, a
  counter). Same-type events queue and run one-at-a-time to completion; the
  read-before-await race is impossible.
- **`droppable`** — for **exclusive flows** (flush, connect, pick): a same-type
  event arriving while one runs is ignored. Replaces a manual `if (_busy) return`.
- **`concurrent`** (default) — for **genuinely independent** events.

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
8. **`close()` must release everything** it created — cancel every subscription
   and timer, dispose seams — before `super.close()`.
9. **Fail loud.** Missing/invalid input → `emitFailure` or throw with a reason;
   never silently fall back to a default. Multi-sink blocs isolate each sink
   (try/catch per sink) so one failure can't break the rest.

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
`bloc.state` (and on emitted `status.event?.groupsToRebuild` to verify selective
rebuilds). A common helper: `Future<void> settle([int ms = 20]) => Future.delayed(...)`.

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
