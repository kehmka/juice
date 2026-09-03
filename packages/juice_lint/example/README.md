# juice_lint — what it catches, what you see, what to do

`juice_lint` turns three idioms from Juice's `AGENTS.md` into analyzer
rules. Each one flags a mistake that compiles cleanly and fails quietly at
runtime. This walkthrough shows, per rule, the offending code, the exact
warning you get, and the fix.

`lib/fixtures.dart` in this directory is the same material as a
self-verifying test: every marked line must trip its rule, every unmarked
line must stay clean.

## Running it

```yaml
# pubspec.yaml
dev_dependencies:
  custom_lint: ^0.8.1
  juice_lint: ^0.1.0
```

```yaml
# analysis_options.yaml
analyzer:
  plugins:
    - custom_lint
```

```sh
dart run custom_lint
```

The IDE's analysis server shows the warnings inline. `flutter analyze`
and `dart analyze` load the plugin but do **not** report its diagnostics,
so on the command line and in CI, `dart run custom_lint` is the runner.

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
lib/blocs/load_events.dart:3:7 • A generic EventBase subclass never matches a typeOfEvent builder (events are matched by exact runtime type). • juice_generic_event • WARNING
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
lib/blocs/cart_state.dart:2:3 • A BlocState field must be final — state is an immutable value changed only through copyWith. • juice_mutable_state_field • WARNING
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
lib/blocs/search_state.dart:3:3 • BlocState holds data, not behavior — move functions, timers, subscriptions, and controllers to the bloc or its config. • juice_behavior_in_state • WARNING
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

## Suppressing a rule

Project-wide, in `analysis_options.yaml`:

```yaml
custom_lint:
  rules:
    - juice_behavior_in_state: false
```

Or on one line:

```dart
// ignore: juice_mutable_state_field
int scratch = 0;
```

## Scope

All three rules key on Juice's own base types
(`package:juice` `EventBase` and `BlocState`). A class from another package
that happens to share a name is never touched, and a plain class with
identical fields (see `NotAState` in `lib/fixtures.dart`) gets no lints.
