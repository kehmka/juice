---
card_schema: "1.0"
package: juice_lifecycle
version: 0.1.0
requires:
  juice: ">=1.4.0"
updated: 2026-06-09
---

# juice_lifecycle — AI card

> App lifecycle (foreground/background/resume) as a bloc, behind a swappable
> provider seam. An **ambient signal** consumers react to (re-check permissions
> on resume, reconnect a socket, blur in the task switcher). Read repo
> `AGENTS.md` for the Juice mental model + gotchas.

## Purpose

**Owns:** the `AppLifecycle` phase + the previous phase.
**Does NOT own:** what to do on a transition — consumers decide. Nothing is
persisted. No third-party dependency (Flutter itself is the source).

## When to use

You need to react to the app moving between foreground/background — privacy
blur, "refresh on resume", pause expensive work in the background. The
`resumedFromBackground` getter is the common trigger.

## Install

```yaml
dependencies:
  juice_lifecycle: ^0.1.0
```

## Construct

Provider is **optional** — defaults to `WidgetsLifecycleProvider` (wraps
Flutter's `AppLifecycleListener`):

```dart
final lifecycle = LifecycleBloc.withConfig(LifecycleConfig(
  // provider: FakeLifecycleProvider(),   // optional; default wraps AppLifecycleListener
));
```

`withConfig` sends `InitializeLifecycleEvent`, which starts the subscription and
emits the provider's `current` phase immediately.

## Seams

```dart
// Vendor seam. OPTIONAL (default WidgetsLifecycleProvider).
abstract class LifecycleProvider {
  Stream<AppLifecycle> get changes;
  AppLifecycle get current;   // read synchronously at init
  Future<void> dispose();
}

enum AppLifecycle { resumed, inactive, paused, detached, hidden }
//  mirrors Flutter's AppLifecycleState 1:1
```

## API

```dart
LifecycleProvider get provider;   // valid after init
Future<void> close();             // cancels subscription, disposes provider
```

There are no convenience send-methods — lifecycle is a *read* signal; consumers
observe state. Drive transitions through the provider (or a fake in tests).

## Events

| Event | Effect | Groups |
|---|---|---|
| `InitializeLifecycleEvent(config)` | configure provider, start listening, emit current phase | `lifecycle:state` |
| `LifecycleChangedEvent(phase)` *internal* | emit only when the phase changes, tracking `previous` | `lifecycle:state` |

## State

```dart
class LifecycleState extends BlocState {
  final AppLifecycle lifecycle;          // default: resumed
  final AppLifecycle? previous;          // null before the first transition
  final DateTime? lastChangedAt;
  bool get isForeground;                 // resumed
  bool get isBackground;                 // paused | hidden
  bool get resumedFromBackground;        // resumed, coming from paused/hidden/inactive
  static const initial = LifecycleState();
}
```

## Rebuild groups

| Group | Emitted when |
|---|---|
| `LifecycleGroups.state` → `lifecycle:state` | the lifecycle phase changed |

Same-phase re-emits are a no-op (no rebuild).

## Recipes

```dart
// 1. Privacy blur in the task switcher (selective rebuild)
class PrivacyShield extends StatelessJuiceWidget<LifecycleBloc> {
  PrivacyShield({super.key}) : super(groups: {LifecycleGroups.state});
  @override Widget onBuild(BuildContext c, StreamStatus s) =>
      bloc.state.isForeground ? const AppBody() : const BlurredScreen();
}

// 2. "Refresh on resume" — listen to the stream, act on resumedFromBackground
final sub = lifecycle.stream.listen((s) {
  if (s.state.resumedFromBackground) {
    permissions.check(JuicePermission.notification); // re-read what the OS may have changed
    dataBloc.refresh();
  }
});
```

## Testing

Headless — drive a fake provider:

```dart
class FakeLifecycleProvider implements LifecycleProvider {
  final _ctrl = StreamController<AppLifecycle>.broadcast();
  AppLifecycle _current = AppLifecycle.resumed;
  @override Stream<AppLifecycle> get changes => _ctrl.stream;
  @override AppLifecycle get current => _current;
  @override Future<void> dispose() async => _ctrl.close();
  void emit(AppLifecycle p) { _current = p; _ctrl.add(p); }
}

final fake = FakeLifecycleProvider();
final bloc = LifecycleBloc.withConfig(LifecycleConfig(provider: fake));
await settle();
fake.emit(AppLifecycle.paused);
await settle();
fake.emit(AppLifecycle.resumed);
await settle();
expect(bloc.state.resumedFromBackground, isTrue);   // previous == paused
```

## Failure modes

- A provider throwing from `changes`/`dispose` surfaces as a bloc failure;
  `lifecycle` keeps its last value.
- This is a live signal, not a queue — phases emitted before a listener attaches
  are not replayed (but `current` seeds the initial state).

## Anti-patterns

- ❌ Putting transition *policy* (reconnect logic, cache flush) inside this
  package — emit the signal, let consumers act.
- ❌ Persisting the phase — it's ephemeral, re-read from the OS each launch.
- ❌ Using `StatefulWidget` + `WidgetsBindingObserver` alongside this bloc for
  the same concern — pick one source of truth.

## Integrates with

- **juice_permissions** — on `resumedFromBackground`, re-`check()` permissions
  the user may have changed in Settings while backgrounded.
- **juice_connectivity / juice_realtime** — reconnect on resume.

## Invariants

- `previous` is set to the prior phase on every real change; `resumedFromBackground`
  is true only for `resumed` arriving from `paused`/`hidden`/`inactive`.
- `WidgetsLifecycleProvider` maps a null binding state to `resumed`.
- `close()` cancels the subscription and disposes the provider.

## See also

`SPEC.md` (design) · `README.md` (narrative) · repo `AGENTS.md` (framework).
