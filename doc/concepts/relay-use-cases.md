# Cross-Bloc Communication

Blocs stay independent: none calls into another's use cases, and none reads
another's private fields. When one bloc's behaviour depends on another, pick
the tool by what it needs.

| The bloc needs to… | Use | Owned by |
|---|---|---|
| follow another bloc's state | a **reaction** — `react(Reaction…)` | the bloc that reacts |
| wait until another bloc reaches a state | **`waitFor`** | the use case that waits |
| get the outcome of an operation | **`sendForResult`** on a `ResultEvent<T>` | the caller |
| do something later | **`sendAfter`** | the bloc that will do it |

> `StateRelay`, `StatusRelay` and `EventSubscription` are deprecated and will
> be removed in 3.0.0. See [The deprecated relays](#the-deprecated-relays)
> below and the [migration guide](../guides/moving-from-relays-to-reactions.md).

## Reactions

A reaction says: when that bloc's state does this, send me that event.

```dart
class NotesBloc extends JuiceBloc<NotesState> {
  NotesBloc() : super(const NotesState(), [/* use cases */]) {
    react(Reaction<SettingsBloc, SettingsState>.changes(
      (settings) => (settings.sortOrder, settings.viewMode),
      send: (settings) => SettingsChangedEvent(
        sortOrder: settings.sortOrder,
        viewMode: settings.viewMode,
      ),
      atAttach: AtAttach.catchUp,
    ));
  }
}
```

The destination attaches it in its own constructor body and owns it: the
reaction ends when the destination closes. `SettingsBloc` knows nothing about
it — it only emits its own state.

### The three forms

```dart
// The predicate went from false to true.
Reaction<AuthBloc, AuthState>.becomes(
  (s) => s.isAuthenticated,
  send: (s) => LoadProfileEvent(userId: s.user!.id),
  atAttach: AtAttach.catchUp,
)

// The selected value is no longer == to what it was.
Reaction<CartBloc, CartState>.changes(
  (s) => s.total,
  send: (s) => UpdateTotalEvent(s.total),
  atAttach: AtAttach.catchUp,
)

// Any edge you can state over the old state and the new one.
Reaction<PowerBloc, PowerState>.edge(
  (old, now) => old.isPluggedIn && !now.isPluggedIn,
  send: (_) => PauseWorkEvent(),
)
```

Every form judges one emission: the state before it against the state after
it. A reaction keeps no memory of its own.

To watch several fields, select a record — records compare by value:
`(s) => (s.sortOrder, s.viewMode)`.

### A reaction sees state, and nothing else

It is shown `oldState` and `state` for every emission of the source, whatever
kind of status carried them. It is never shown the status kind, the event, or
the rebuild groups. That is deliberate:

- If the destination needs to know the source is busy or failed, the source
  says so in its state (`isSyncing`, `lastError`).
- If someone needs the outcome of one operation, that is a
  [typed result](#outcomes-are-typed-results) for the caller, not a reaction.

### What the state at attach means

`becomes` and `changes` take a required `atAttach`. There is no default,
because either answer is wrong somewhere.

- `AtAttach.catchUp` — the state the source is already in counts: `becomes`
  fires if its predicate holds now, `changes` fires once with the current
  value. Use it when the destination must not depend on which bloc was built,
  or finished loading, first. This is the usual answer.
- `AtAttach.skip` — only a change from now on counts.

`edge` has no meaning at attach (there is no old state) and takes none.

### Which source

Without `source:`, the reaction resolves its source type through `BlocScope`
(`scope:` picks a scoped registration). The source must be registered before
the reacting bloc is built.

A reaction holds no lease and never keeps its source alive. So a `leased`
source cannot be resolved by type — pass the instance, from the code that
holds its lease:

```dart
editorPreview.react(Reaction<EditorBloc, EditorState>.changes(
  (s) => s.text,
  source: editorLease.bloc,
  send: (s) => RenderPreviewEvent(s.text),
  atAttach: AtAttach.catchUp,
));
```

When the source closes, the reaction ends (recorded as `reaction` / `end`).

### When the event is sent

The edge is judged inside the emission; the event is sent a microtask later,
never inside the use case that emitted. A catch-up at attach is sent the same
way.

`react` returns a `ReactionBinding`. Call `cancel()` to detach early; nothing
is sent after it ends.

### Chains and rings

A reaction's event can cause another reaction. The framework counts the hops
and refuses to send past `Reaction.maxHops` (8): the hop is not sent and an
error is recorded (`reaction` / `refused`). That is either a ring — two blocs
reacting to each other — or a chain that should be one use case. The reaction
stays attached.

A callback of yours that throws (the predicate, the selector, `send`) is
recorded as an error (`reaction` / `error`) and never reaches the use case
that emitted. The reaction stays attached.

## Waiting for a state: `waitFor`

When a use case cannot proceed until another bloc is ready:

```dart
final session = await sessionBloc.waitFor(
  (s) => s.isReady,
  timeout: const Duration(seconds: 10),
);
```

It returns the state that satisfied the predicate — at once, if the current
state already does. The timeout is required. Every other exit is loud: a
`TimeoutException`, a `StateError` if the bloc closes, a `CancelledException`
in a `restartable` run that was superseded.

## Outcomes are typed results

The outcome of an operation belongs to whoever asked for it:

```dart
class RefreshTokenEvent extends ResultEvent<AuthSession> {}

final session = await authBloc.sendForResult(RefreshTokenEvent());
```

The use case emits a terminal status and calls `event.succeed(value)`. A
failure status throws from `sendForResult`.

Two rules for the use case:

- A waiter is answered by the FIRST status that is not a waiting one. If that
  is an in-progress update (`isRefreshing: true`), the waiter is already past
  it and waiting on the value — so a later failure must call
  `event.fail(error, stackTrace)` as well as `emitFailure`.
- To refuse an event without emitting anything, `event.fail(error)` and
  return: `sendForResult` throws that error.

When several callers may ask at once, register the event
`EventConcurrency.singleflight`. A second event joins the run in flight and is
answered by it — one provider call, every caller gets the session.
`joinKey:` narrows the join to events with equal keys:

```dart
() => UseCaseBuilder(
  typeOfEvent: RequestPermissionEvent,
  useCaseGenerator: () => RequestPermissionUseCase(),
  concurrency: EventConcurrency.singleflight,
  joinKey: (event) => (event as RequestPermissionEvent).permission,
),
```

## Doing something later: `sendAfter`

```dart
void typed(String text) =>
    sendAfter(SearchEvent(text), const Duration(milliseconds: 300),
        key: 'search');
```

The bloc owns the timer. A later `sendAfter` with the same key replaces the
pending one — its event is never sent — which is a debounce.
`cancelSend('search')` cancels by name; the returned `DelayedSend` cancels an
anonymous one. A close discards whatever is pending and records it.

For periodic work, bind a periodic stream:

```dart
bindStream<void>(
  Stream<void>.periodic(const Duration(minutes: 1)),
  (_) => send(CheckPowerEvent()),
  key: 'poll',
);
```

No `Timer` field, no `isClosed` guard, no cancel in `close()`.

## A coordinator is a bloc

Orchestration across several blocs needs no special type. Write a bloc whose
events are the ones reactions send it and whose use cases call `waitFor` and
`sendForResult` on the others.

## The deprecated relays

`StateRelay`, `StatusRelay` and `EventSubscription` still work and are removed
in 3.0.0.

A relay sent an event on EVERY emission of its source and was owned by nobody:
it leased both blocs and lived until something closed it. A reaction says
which change it means and is owned by its destination.

Two uses have no drop-in replacement, on purpose:

- a `StatusRelay` that mapped a waiting or failure **status** to an event;
- an `EventSubscription` keyed on a source **event type**.

Both looked at something that is not state. Put what the destination needs in
a state field of the source and react to that, or give the caller a typed
result. The [migration guide](../guides/moving-from-relays-to-reactions.md)
walks through each.

## Next Steps

- Learn how to [test blocs that talk to each other](../testing/testing-relay-use-cases.md)
- Review the [migration guide](../guides/moving-from-relays-to-reactions.md)
