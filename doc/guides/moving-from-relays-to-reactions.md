---
layout: default
title: Moving from relays to reactions
parent: Guides
nav_order: 98
---

# Moving from relays to reactions

`StateRelay`, `StatusRelay` and `EventSubscription` are deprecated and will be
removed in 3.0.0. They keep working until then. This guide shows what replaces
each use, and the two uses that have no drop-in replacement.

The short version:

| You wrote | Write instead |
|---|---|
| `StateRelay` that follows another bloc's state | `react(Reaction…)` in the destination's constructor |
| `StatusRelay` / `EventSubscription` watching for an operation to finish | `await bloc.sendForResult(Event())` in the caller |
| A `Completer` on an event, or a `fooNow()` twin method | make the event a `ResultEvent<T>` |
| A `Timer` field for a debounce or a delay | `sendAfter(event, delay, key: …)` |
| A `Timer.periodic` field | `bindStream(Stream<void>.periodic(d), …, key: …)` |
| A `droppable` event that callers await | `EventConcurrency.singleflight` |
| `await Future.delayed(…)` in a multi-bloc test | `juiceFlowTest` |

## A relay that follows state

Before, in the composition root, after both blocs were registered:

```dart
StateRelay<SettingsBloc, NotesBloc, SettingsState>(
  toEvent: (state) => SettingsChangedEvent(
    sortOrder: state.sortOrder,
    viewMode: state.viewMode,
  ),
);
```

After, in the destination:

```dart
class NotesBloc extends JuiceBloc<NotesState> {
  NotesBloc() : super(const NotesState(), [/* … */]) {
    react(Reaction<SettingsBloc, SettingsState>.changes(
      (s) => (s.sortOrder, s.viewMode),
      send: (s) => SettingsChangedEvent(
        sortOrder: s.sortOrder,
        viewMode: s.viewMode,
      ),
      atAttach: AtAttach.catchUp,
    ));
  }
}
```

Three things changed, and each is deliberate.

**The destination owns it.** A relay was owned by nobody: it leased both blocs
and lived until someone remembered to close it. A reaction ends when its
destination closes, or when its source does.

**It says which change it means.** A relay sent on every emission of the
source. A reaction sends when the state does what it describes:

- `Reaction.becomes(predicate)` — the predicate went from false to true;
- `Reaction.changes(select)` — the selected value is no longer `==`;
- `Reaction.edge((old, now) => …)` — any other edge.

If your relay had a `when:` filter, that filter is usually the predicate of a
`becomes`. If it sent the whole state on, pick the fields the destination
actually uses and `select` them (a record compares by value).

**It says what the state at attach means.** `atAttach` has no default.
`AtAttach.catchUp` sends once for the state the source is already in, so the
destination does not depend on which bloc was built or loaded first. That is
the usual answer. `AtAttach.skip` waits for the next change.

A `leased` source cannot be resolved by type, because a reaction holds no
lease. Pass the instance: `Reaction<…>.changes(…, source: editorBloc, …)`.

## The two uses with no drop-in replacement

A reaction sees state and nothing else. Two things the old classes could see
are gone on purpose.

**A `StatusRelay` that mapped a waiting or failure status to an event.** The
status of an operation is not state. Either put what the destination needs in
a state field of the source (`isSyncing`, `lastError`) and react to that, or —
when it is the outcome of one operation — let the caller take it:

```dart
try {
  final session = await auth.sendForResult(RefreshTokenEvent());
  // …
} on RefreshFailedError {
  // …
}
```

**An `EventSubscription` keyed on a source event type.** "When `AuthBloc`
handles `LoginSuccessEvent`, load the profile" becomes "when `AuthBloc`'s
state becomes authenticated, load the profile":

```dart
react(Reaction<AuthBloc, AuthState>.becomes(
  (s) => s.isAuthenticated,
  send: (s) => LoadProfileEvent(userId: s.user!.id),
  atAttach: AtAttach.catchUp,
));
```

If no state field tells the destination what it needs, add one to the source.
That is the port.

## Outcomes are typed results

An event whose caller wants the answer extends `ResultEvent<T>`. Its use case
emits a terminal status and calls `event.succeed(value)`:

```dart
class RefreshPageEvent extends ResultEvent<void> { … }

await paging.sendForResult(RefreshPageEvent());   // what a pull-to-refresh awaits
```

Two rules for the use case:

- A waiter is answered by the FIRST status that is not a waiting one. If that
  is an in-progress update, the waiter is already past it and waiting on the
  value, so a later failure must call `event.fail(error, stackTrace)` as well
  as `emitFailure`.
- To refuse an event without emitting anything, `event.fail(error)` and return.
  `sendForResult` throws that error.

If several callers may ask at once, register the event
`EventConcurrency.singleflight`: a second event joins the run in flight and is
answered by it. `droppable` would fail the second caller. Add
`joinKey: (e) => …` to join only events with equal keys.

## Timers

```dart
// Before: a Timer? field, a cancel before re-arming, an isClosed guard in
// the callback, a cancel in close().
// After:
sendAfter(SearchEvent(text), kDebounce, key: 'search');   // the key replaces
cancelSend('search');
```

The bloc owns the timer. A close discards a pending send and records it as a
warning; a bloc that routinely closes with one pending calls `cancelSend` in
its own `close` first.

## Tests

A test of several blocs no longer sleeps:

```dart
juiceFlowTest('a settings change reaches notes', (flow) async {
  final settings = flow.register<SettingsBloc>(() => SettingsBloc());
  final notes = flow.register<NotesBloc>(() => NotesBloc());

  await flow.send(settings, ToggleViewModeEvent());

  flow.expect(settings, [isUpdatingStatus(state: isGrid)]);
  flow.expect(notes, [isUpdatingStatus(state: isGrid)]);
});
```

`flow.send` waits until every bloc is idle. The test fails on any emission it
did not assert, on work still in flight at the end, and on a chain of
reactions longer than `Reaction.maxHops`. Add `virtualTime: true` to make
every timer virtual; a test that waits on real I/O under it fails at once,
saying so.

## Package changes that come with this

- **juice_forms**: `ValidateFormEvent` and `SubmitFormEvent` no longer take
  `completion:`. `validateNow()` and `submitNow()` are deprecated for
  `sendForResult`. `sendForResult(SubmitFormEvent())` returns `false` for an
  invalid form and throws when no handler is configured or the handler threw;
  `submitNow()` answered `false` for those.
- **juice_permissions**: `PermissionsBloc.requestsInFlight` is gone. The
  per-permission singleflight is the event's registration.
- **juice_auth**, **juice_paging**: `RefreshTokenEvent` and `RefreshPageEvent`
  are `singleflight`, where they were `droppable`. Nothing changes for a
  caller that does not await them.
