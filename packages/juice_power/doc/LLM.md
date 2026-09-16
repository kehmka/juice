---
card_schema: "1.0"
package: juice_power
version: 0.1.0
requires:
  juice: ">=1.6.0"
  battery_plus: ">=6.2.0"
updated: 2026-09-16
---

# juice_power — AI card

> Battery and charging state as a bloc: plugged-in, charge level, OS
> power-saver, behind a swappable provider seam. An **ambient signal** other
> code consumes to decide *when it may be expensive* (background inference,
> transcoding, uploads, sync). Read repo `AGENTS.md` for the Juice mental model
> + gotchas.

## Purpose

**Owns:** charging `status`, charge `percent`, OS power-saver flag.
**Does NOT own:** policy about any of them. "Pause on battery", "stop below
20%", "ask first" belong to the consumer, which alone knows what the work
costs. Nothing is persisted (ephemeral signal).

## When to use

You have work expensive enough that a user would resent it on a dying battery —
on-device inference, video export, a big sync. Pair with `juice_connectivity`
when the work also needs a network, and `juice_lifecycle` when foreground
matters.

## Install

```yaml
dependencies:
  juice_power: ^0.1.0   # pulls battery_plus for the default provider
```

## Construct

```dart
final power = PowerBloc.withConfig(PowerConfig(
  // provider: MyPowerProvider(),               // optional; default = BatteryPlusProvider
  pollInterval: const Duration(minutes: 1),     // level re-read; Duration.zero disables
));
```

`withConfig` sends `InitializePowerEvent`, which subscribes, starts the poll,
**and** does an immediate `check()` so state is real at once — without it a
consumer that boots and asks "may I run?" reads `initial`, whose `unknown`
status answers *no*, and stalls until the next physical power change.

## Seams

```dart
// Vendor seam. OPTIONAL (default BatteryPlusProvider).
abstract class PowerProvider {
  Stream<PowerSnapshot> get changes;  // platform status-change stream
  Future<PowerSnapshot> check();      // one-shot current reading (also the poll)
  Future<void> dispose();
}

class PowerSnapshot { final BatteryStatus status; final int? percent; final bool? saverOn; }
//  percent == null  → the platform will not say (Simulator answers -1; some devices throw)
//  saverOn == null  → the platform will not say
```

Providers stream **status**, not level — hence the bloc's poll. A custom
provider needs no timer of its own.

## API

```dart
PowerProvider get provider;   // valid after init
void check();                 // one-shot manual re-read
Future<void> close();         // cancels poll + subscription, disposes provider
```

## Events

| Event | Effect | Concurrency | Groups |
|---|---|---|---|
| `InitializePowerEvent(config)` | configure, subscribe, start poll, emit immediate reading | `droppable` (a second init would leak a timer) | changed groups |
| `PowerChangedEvent(snapshot)` *internal* | emit only on actual change | `sequential` (read-compare-emit) | changed groups only |
| `CheckPowerEvent` | one-shot re-read; also the poll tick | `droppable` (coinciding reads report the same instant) | changed groups only |

## State

```dart
class PowerState extends BlocState {
  final BatteryStatus status;   // unknown | discharging | charging | full | connectedNotCharging
  final int? percent;           // null = unknown
  final bool? saverOn;          // null = unknown
  final DateTime? lastChangedAt;

  bool get isPluggedIn;         // charging | full | connectedNotCharging  (unknown → FALSE)
  bool get isOnBattery;         // discharging only
  bool get saverAsked;          // saverOn == true   (unknown → false)
  bool isAtOrBelow(int pct);    // FALSE when percent is null
  static const initial = PowerState();
}
```

### Unknown handling — the invariant to preserve

Every unknown resolves **conservatively**, toward not burning power. Do not
"simplify" these into defaults; each guess is wrong in a way that matters:

| Reading | Unknown → | Guessing the other way |
|---|---|---|
| `status` | not plugged in | starts expensive work on battery during every cold boot |
| `percent` | `isAtOrBelow` false | a fabricated `0` shuts every gate on a full battery |
| `saverOn` | `saverAsked` false | `false` is permissive — grants power-burning permission on a device that asked to conserve |

`copyWith` uses an `_unset` sentinel for **both** `percent` and `saverOn`, so a
reading that goes unknown can actually CLEAR them. With a plain `??` a device
that stopped reporting would serve its last number forever.

## Rebuild groups

| Group | Emitted when |
|---|---|
| `PowerGroups.source` → `power:source` | plugged in / unplugged |
| `PowerGroups.level` → `power:level` | charge level moved |
| `PowerGroups.saver` → `power:saver` | OS power saver toggled |

Only groups that actually changed are emitted; an unchanged reading is a no-op
(the poll would otherwise wake every consumer once a minute for nothing).

## Recipes

```dart
// 1. Gate expensive work on a relay — NOT a stream.listen with a _wasPlugged field.
StateRelay<PowerBloc, WellBloc, PowerState>(
  toEvent: (_) => PauseWellEvent(),
  when: (s) => s.oldState.isPluggedIn && !s.state.isPluggedIn,
);
StateRelay<PowerBloc, WellBloc, PowerState>(
  toEvent: (_) => ResumeWellEvent(),
  when: (s) => !s.oldState.isPluggedIn && s.state.isPluggedIn,
);

// 2. The gate itself, inside the use case that does the work — so it refuses
//    rather than trusting whoever sent the event.
if (!bloc.power.state.isPluggedIn && onlyWhileCharging) return;

// 3. Badge with selective rebuild
class ChargeBadge extends StatelessJuiceWidget<PowerBloc> {
  ChargeBadge({super.key}) : super(groups: {PowerGroups.source, PowerGroups.level});
  @override Widget onBuild(BuildContext c, StreamStatus s) =>
      Text(bloc.state.percent == null ? '—' : '${bloc.state.percent}%');
}
```

## Out of scope

**Thermal state** — the other reason to back off, deliberately absent: no
package in this family ships native code and there is no cross-platform Flutter
source for `ProcessInfo.thermalState`. Add a channel in the app and combine it
with this state.

## Testing

Headless — drive a fake provider; no device. Every transition is one line:

```dart
final fake = FakePowerProvider();
final bloc = PowerBloc.withConfig(PowerConfig(provider: fake, pollInterval: Duration.zero));
fake.emit(const PowerSnapshot(status: BatteryStatus.discharging, percent: 12));
fake.setSilently(...);   // a level that moves with NO status change → only the poll sees it
```

## Failure modes

- **The default provider never throws for a reading it cannot make.** An
  out-of-range or unreadable level and an unreadable saver flag become `null`
  (unknown) with a log line — the Simulator's `-1` and the Android devices
  that throw both land here. Unknown is then handled by the State invariants
  above, never by a fabricated number.
- **A custom provider that throws from `check()`** fails `InitializePowerEvent`
  / `CheckPowerEvent` loudly through the framework's use-case error path
  (`use_case_error`, the bloc error handler). There is no `emitFailure`: state
  is left as it was (on a cold boot, `initial` — which answers "may I run?"
  with *no*). Make the provider report unknown instead of throwing.
- **An error on `changes`** is not caught by the bloc's subscription (no
  `onError`); a provider's stream must not error. Report unknown snapshots
  instead.
- `pollInterval: Duration.zero` disables the poll: the level then moves only
  when the platform pushes a status change.

## Anti-patterns

- ❌ A `_wasPluggedIn` field and a `stream.listen` in the consumer to detect
  the unplug — that is a relay (`StateRelay`, Recipe 1). The bloc already
  emits only real changes with precise groups.
- ❌ Policy in the bloc or the provider ("pause below 20%"). It belongs in the
  use case that does the expensive work (Recipe 2), which alone knows the cost.
- ❌ Treating a `null` `percent` / `saverOn` as `0` / `false`. Each is wrong in
  a way that matters — see the unknown-handling table under State.
- ❌ Asking "may I run?" before the immediate `check()` has resolved and
  reading `initial` as an answer. `withConfig` issues that check for exactly
  this; give it a tick.
- ❌ Constructing a second `PowerBloc` for a second consumer — that is a second
  poll timer. One bloc, many relays.

## Invariants

- **Unknown is conservative.** `status` unknown → not plugged in; `percent`
  unknown → `isAtOrBelow` is false; `saverOn` unknown → `saverAsked` is false.
  `copyWith` can CLEAR `percent` and `saverOn` (an `_unset` sentinel), so a
  device that stops reporting does not serve its last number forever.
- **Only what changed is emitted.** An unchanged reading is a no-op — no
  emission, no `lastChangedAt` — so the poll never wakes consumers for nothing.
- **`withConfig` reads immediately**; state is real before the first physical
  change.
- **`close()` cancels the poll and the subscription, then disposes the
  provider** — nothing outlives the bloc.

## See also

`SPEC.md` (the thermal-state decision, why unknown is conservative) ·
`README.md` (narrative) · siblings `juice_connectivity` (network gate) and
`juice_lifecycle` (foreground gate) · repo `AGENTS.md` (framework; §3 relays).
