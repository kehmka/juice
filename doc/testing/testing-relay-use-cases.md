# Testing Blocs That Talk to Each Other

`juiceTest` tests one bloc. When the behaviour under test crosses blocs — a
reaction, a chain of them, a debounce in the middle — use `juiceFlowTest`. It
knows when every bloc is idle, so a test never sleeps, and it fails on
anything the test did not account for.

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:juice/juice.dart';
import 'package:juice/testing.dart';

void main() {
  juiceFlowTest('a settings change reaches notes', (flow) async {
    final settings = flow.register<SettingsBloc>(() => SettingsBloc());
    final notes = flow.register<NotesBloc>(() => NotesBloc());

    await flow.send(settings, ToggleViewModeEvent());

    flow.expect(settings, [
      isUpdatingStatus(state: isA<SettingsState>()
          .having((s) => s.viewMode, 'viewMode', ViewMode.grid)),
    ]);
    flow.expect(notes, [
      isUpdatingStatus(state: isA<NotesState>()
          .having((s) => s.viewMode, 'viewMode', ViewMode.grid)),
    ]);
  });
}
```

## Handing blocs to the flow

- `flow.register<T>(() => T())` registers the bloc in `BlocScope` as
  permanent, builds it at once and watches it. Use it when another bloc finds
  this one by type — a reaction without `source:`, a `BlocScope.get`.
- `flow.add(bloc)` watches an instance the test built. Use it for a bloc that
  is passed around by instance.

Register a source before the bloc that reacts to it, as an app would.

Build blocs inside the flow and without a `logger:` of their own. The flow
reads errors from its own logger and refuses to watch a bloc that reports
elsewhere.

A bloc you do not hand to the flow is not recorded, and the flow does not
close it. Its sends are still waited for.

The flow owns `BlocScope` for the test. It will not start while anything is
registered there, and it resets the scope when it ends.

## Acting and settling

- `await flow.send(bloc, event)` sends and waits until every bloc is idle:
  the run it starts, every reaction that follows, and every run those start.
- `await flow.settle()` waits alone, after something else acted — a plain
  `bloc.send(...)`, a bloc method, a fake provider emitting.

Idle means no send in flight (one waiting in a `sequential` queue counts), no
reaction hop pending, and no `sendAfter` still waiting to fire.

A settle that has not gone idle in 5 seconds fails, naming what is still in
flight. Pass `timeout:` for something slower.

## Asserting

`flow.expect(bloc, expected)` asserts on what that bloc emitted since its last
`expect`, exactly and in order, and consumes it.

```dart
await flow.send(cart, AddItemEvent(apple));
flow.expect(cart, [isUpdatingStatus(state: hasItems(1))]);
flow.expect(summary, [isUpdatingStatus(state: hasTotal(120))]);

await flow.send(cart, AddItemEvent(pear));
flow.expect(cart, [isUpdatingStatus(state: hasItems(2))]);   // only the new one
flow.expect(summary, [isUpdatingStatus(state: hasTotal(200))]);
```

- One matcher per emission: `isUpdatingStatus`, `isWaitingStatus`,
  `isFailureStatus`, `isCancelingStatus`, each taking `state:` and `groups:`.
- Or one matcher over the whole list: `isEmpty`, `hasLength(2)`.
- Order is asserted per bloc, not across blocs.

## What fails the test

When the body returns, the flow closes every bloc it holds and fails if:

- a watched bloc emitted something no `flow.expect` consumed;
- a send, a hop or a delayed send was still in flight — end on `flow.send` or
  `flow.settle()`;
- a chain of reactions was refused for running past `Reaction.maxHops`;
- an error was recorded that the test did not claim;
- anything emitted while the blocs were closing.

Every problem is listed in the one failure.

### Errors

An error-level telemetry entry is an error: a use case that threw, a reaction
callback that threw, a stream-binding error, an event with no use case. Claim
the ones you expect:

```dart
await flow.send(cart, BrokenEvent());
flow.expectErrors([isA<StateError>()]);
```

A failure the use case handled itself (`emitFailure`) is an emission, asserted
with `isFailureStatus(error: …)`. A refused reaction chain cannot be claimed.

## Time

A pending `sendAfter` is not idle, so `flow.send` and `flow.settle()` wait a
debounce out. To act in the middle of a delay, let a stated amount of time
pass without waiting for idle:

```dart
juiceFlowTest('a second keystroke replaces the search', (flow) async {
  final shelf = flow.add(ShelfBloc());

  shelf.typed('j');                                     // sendAfter, 300 ms
  await flow.elapse(const Duration(milliseconds: 100));
  shelf.typed('ju');                                    // replaces it
  await flow.settle();

  flow.expect(shelf, [isUpdatingStatus(state: hasResultsFor('ju'))]);
}, virtualTime: true);
```

By default a flow runs on the real clock: a 300 ms debounce takes 300 ms.

With `virtualTime: true` the same test runs on a virtual clock. Whenever the
test is waiting and nothing can happen until time passes, the clock jumps to
the next timer. Every timer is virtual — a `sendAfter`, a `Future.delayed` in
a use case, a `waitFor` timeout, the settle limit — so the test takes no time.
A timer that re-arms itself forever never goes idle and fails after 5 virtual
seconds.

A virtual clock cannot advance the real world. Hive, sqflite and platform
channels never complete under it, and a test that waits on one fails at once,
saying so. Fake the seam, or leave that test on the real clock.

## In a test with its own setup

`runJuiceFlow` is the body of `juiceFlowTest`:

```dart
test('with my own setup', () async {
  final provider = FakeProvider();
  await runJuiceFlow((flow) async {
    final bloc = flow.add(MyBloc(provider));
    // …
  });
});
```

Inside `testWidgets`, call it through `tester.runAsync`.

## One bloc

For a single bloc, [`juiceTest`](../../AGENTS.md#6-build--test) is shorter:
build, act, and assert on exactly what it emitted.

## The deprecated relays

`StateRelay`, `StatusRelay` and `EventSubscription` are deprecated; port them
with the [migration guide](../guides/moving-from-relays-to-reactions.md). A
flow does not count a relay's sends as work in flight, so a test that mixes a
relay with a flow can fail on a late emission. Port the relay first.

## Next Steps

- Read [Cross-Bloc Communication](../concepts/relay-use-cases.md) for the tools under test
