# juice_lint — what it catches, what you see, what to do

`juice_lint` turns idioms from Juice's `AGENTS.md` into analyzer rules.
Each one flags a mistake that compiles cleanly and fails quietly at
runtime. This walkthrough shows, per rule, the offending code, the
warning you get, and the fix.

The `lib/` fixtures in this directory are the same material as a
self-verifying test: every `// expect_lint:` marker's rule must be reported
on the line below it, and every other line must stay clean
(`dart run tool/check_fixtures.dart` from `packages/juice_lint`).

## Running it

Nothing in `pubspec.yaml` — enable the plugin in `analysis_options.yaml`,
in a top-level `plugins:` section:

```yaml
plugins:
  juice_lint:
    path: ..            # this directory; consumers use a version or path
```

```sh
dart analyze
```

The rules are reported by `dart analyze` and the IDE (juice_lint 0.1.0, on
custom_lint, only reported through `dart run custom_lint`). `flutter
analyze` on Flutter 3.47.5 exits before plugin results arrive, so it
shows none of them.

## 1 · `juice_generic_event`

**AGENTS.md §5, gotcha 2:** events are matched by exact runtime type.

```dart
class LoadEvent<T> extends EventBase {}   // generic

UseCaseBuilder(
  typeOfEvent: LoadEvent,                 // matches LoadEvent, never LoadEvent<Item>
  useCaseGenerator: () => LoadUseCase(),
)
```

Sending `LoadEvent<Item>()` reaches no use case. Nothing throws. The event
is simply dead.

What you see:

```
warning - lib/blocs/load_events.dart:3:7 - A generic EventBase subclass never matches a typeOfEvent builder (events are matched by exact runtime type). - juice_generic_event
```

The fix is a concrete event per shape you actually send:

```dart
class LoadItemsEvent extends EventBase {}
class LoadUsersEvent extends EventBase {}
```

If the payload varies, carry it as a field, not a type parameter:

```dart
class LoadEvent extends EventBase {
  final String collection;
  LoadEvent(this.collection);
}
```

## 2 · `juice_mutable_state_field`

**AGENTS.md §1:** `BlocState` is immutable; every change goes through
`copyWith`.

```dart
class CartState extends BlocState {
  int itemCount = 0;                      // non-final
  CartState();
}
```

A mutable field can be changed in place, bypassing emission entirely: no
rebuild, no telemetry entry, and `emitUpdate(skipIfSame: true)` compares
against a value that already moved.

What you see:

```
warning - lib/blocs/cart_state.dart:2:3 - A BlocState field must be final — state is an immutable value changed only through copyWith. - juice_mutable_state_field
```

The fix is the canonical state shape: `final` fields, a `const`
constructor, and `copyWith`:

```dart
class CartState extends BlocState {
  final int itemCount;
  const CartState({this.itemCount = 0});

  CartState copyWith({int? itemCount}) =>
      CartState(itemCount: itemCount ?? this.itemCount);
}
```

Changes happen in a use case, through emission:

```dart
emitUpdate(
  newState: bloc.state.copyWith(itemCount: bloc.state.itemCount + 1),
  groupsToRebuild: {CartGroups.count},
);
```

## 3 · `juice_behavior_in_state`

**AGENTS.md §5, gotcha 5:** state holds data, not behavior.

```dart
class SearchState extends BlocState {
  final String query;
  final Timer? debounce;                  // a handle
  final void Function()? onSubmit;        // a callback
  final TextEditingController controller; // a controller
  const SearchState({...});
}
```

The rule flags function-typed fields and anything typed `Timer`,
`StreamSubscription`, `StreamController`, `*Controller`, or `*Bloc`. These
are live objects with lifecycles. Put them in a value type and they get
copied by `copyWith`, compared by `==`, and never disposed by anyone who
knows they exist.

What you see:

```
warning - lib/blocs/search_state.dart:3:3 - BlocState holds data, not behavior — move functions, timers, subscriptions, and controllers to the bloc or its config. - juice_behavior_in_state
```

The fix moves the handle to the bloc, which owns its lifecycle and
disposes it in `close()`; the state keeps only the value:

```dart
class SearchState extends BlocState {
  final String query;
  final bool submitting;
  const SearchState({this.query = '', this.submitting = false});
  SearchState copyWith({String? query, bool? submitting}) => SearchState(
        query: query ?? this.query,
        submitting: submitting ?? this.submitting,
      );
}

class SearchBloc extends JuiceBloc<SearchState> {
  Timer? _debounce;

  @override
  Future<void> close() async {
    _debounce?.cancel();
    await super.close();
  }
}
```

Callbacks become events: instead of storing `onSubmit`, the widget sends
`SubmitSearchEvent()` and a use case handles it.

## 4 · `juice_missing_concurrency_mode` (opt-in)

**AGENTS.md §4:** pick the concurrency mode per event. This is the one
rule that is off by default (the `concurrent` default is legitimate for
independent events); this package enables it under `diagnostics:`.

```dart
() => UseCaseBuilder(typeOfEvent: AddItemEvent, useCaseGenerator: () => AddItemUseCase()),
() => UseCaseBuilder.typed(() => RenameItemUseCase()),
```

Both default to `concurrent`: a second `AddItemEvent` runs while the first
is suspended at an `await`. That may be right — but it should be a
decision. The fix is to say which: `sequential` (mutates shared state),
`droppable` (exclusive flow), or `concurrent` (independent):

```dart
() => UseCaseBuilder.typed(() => AddItemUseCase(),
    concurrency: EventConcurrency.sequential),
```

## 5 · `juice_send_in_build` and 6 · `juice_lease_in_build`

`build`/`onBuild` runs on every rebuild — and emissions cause rebuilds.

```dart
@override
Widget onBuild(BuildContext context, StreamStatus status) {
  bloc.send(RefreshEvent());                  // juice_send_in_build
  final lease = BlocScope.lease<ItemsBloc>(); // juice_lease_in_build
  return TextButton(
    onPressed: () => bloc.send(SaveEvent()),  // a callback: fine
    child: Text('${lease.bloc.state.count}'),
  );
}
```

A send in the build body dispatches on every rebuild (and loops if its
use case emits into this widget's groups). A lease in build takes a new
reference on every rebuild and never releases one, so the bloc can never
be disposed. Send from callbacks or `initState`; lease in `initState`,
release in `dispose`. Only statements directly in the build body are
flagged — closures (`onPressed:`, `builder:`) run later.

## 7 · `juice_stale_read_across_await`

**AGENTS.md §4 — the #1 latent bug.**

```dart
final items = bloc.state.items;             // snapshot
final created = await createRemote(e.name); // another event emits here
emitUpdate(newState: bloc.state.copyWith(items: [...items, created])); // clobbers it
```

The fix: read `bloc.state` after the await (or make the event
`sequential` — though that only serializes events of the same type). The
rule is deliberately narrow — a snapshot of the state or of a collection
in it, crossing an `await`, flowing into `newState:`; see the package
README for the exact heuristic. A deliberate rollback is silenced at the
use with `// ignore: juice_lint/juice_stale_read_across_await`
(`RollbackUseCase` in `lib/use_case_fixtures.dart`).

## Suppressing a rule

Project-wide, under the plugin in `analysis_options.yaml`:

```yaml
plugins:
  juice_lint:
    path: ..
    diagnostics:
      juice_behavior_in_state: false
```

Or on one line — plugin diagnostics take the `juice_lint/` prefix:

```dart
// ignore: juice_lint/juice_mutable_state_field
int scratch = 0;
```

## Scope

Every rule keys on Juice's own types (`package:juice` `EventBase`,
`BlocState`, `UseCase`, `UseCaseBuilder`, `BlocScope`, `JuiceBloc`). A class
from another package that happens to share a name is never touched, and a
plain class with identical fields (see `NotAState` in `lib/fixtures.dart`)
gets no lints.
