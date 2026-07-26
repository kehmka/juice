# juice_power Specification

> **Status:** Implemented (shipping).
> **Package:** `juice_power`
> **Primary Bloc:** `PowerBloc`

## Overview

`juice_power` is an **ambient-signal** foundation bloc: it owns the device's
power situation and nothing else. It is the signal consumed by anything that
must decide *when it is acceptable to be expensive* — background inference,
media transcoding, large uploads, sync flushes.

It sits beside `juice_connectivity` and `juice_lifecycle` in the same family:
small, ephemeral, widely consumed, opinion-free.

## Domain boundary

- **Owns:** charging `status`, charge `percent`, OS power-saver flag.
- **Does NOT own:** any policy about them. "Pause the well on battery",
  "stop below 20%", "ask the user first" are consumer decisions, because the
  right answer depends on the cost of the work and the user's appetite for it.
  A `PowerPolicy` type here would be sprawl: it would have to be configured by
  the consumer anyway, and would only move the decision somewhere the consumer
  cannot see it.

## Dependencies

| Package | Why |
|---------|-----|
| `juice` | core bloc infrastructure |
| `battery_plus` | default provider's platform source |

No `juice_storage` — power is an ephemeral signal, nothing is persisted.

## Vendor seam

```dart
abstract class PowerProvider {
  Stream<PowerSnapshot> get changes;
  Future<PowerSnapshot> check();
  Future<void> dispose();
}
```

`PowerSnapshot` carries `status` / `percent` / `saverOn`. The default
implementation is `BatteryPlusProvider`; the bloc never imports `battery_plus`.

**Why `check()` as well as `changes`.** Platforms signal *status* changes
(plugged/unplugged) readily and *level* changes hardly at all. A provider is
therefore not expected to emit per percentage point, and `PowerBloc` closes the
gap by polling `check()` on `PowerConfig.pollInterval`. Putting the poll in the
bloc rather than in each provider means a fake provider needs no timer of its
own, and the polling behaviour is tested once.

## State

```dart
class PowerState extends BlocState {
  final BatteryStatus status;   // unknown | discharging | charging | full | connectedNotCharging
  final int? percent;           // null = the platform will not say
  final bool? saverOn;          // null = the platform will not say
  final DateTime? lastChangedAt;

  bool get isPluggedIn;         // charging | full | connectedNotCharging
  bool get isOnBattery;         // discharging only
  bool get saverAsked;          // saverOn == true
  bool isAtOrBelow(int pct);    // false when percent is null
}
```

### The unknown-handling invariant

Three readings can be unknown, and each is resolved in the **conservative**
direction — the one that errs toward *not* burning power:

| Reading | Unknown resolves to | Because the other way |
|---|---|---|
| `status` | not plugged in | would let expensive work start on battery during every cold boot, before the first reading lands |
| `percent` | `isAtOrBelow` → false | a fabricated `0` would shut every gate on a full battery; a fabricated `100` would open every gate on an empty one |
| `saverOn` | `saverAsked` → false | `false` is permissive; guessing it grants permission to burn power on a device that asked to conserve |

`percent` and `saverOn` are **nullable in state, not collapsed in the
provider**, so the ambiguity surfaces where a consumer can decide it. The
provider logs (`JuiceLoggerConfig.logger.logError`) rather than swallowing —
fail loud, per the family's rule against silent fallbacks.

`connectedNotCharging` counts as plugged in. iOS reports it when the device is
connected but deliberately holding charge (optimized charging, a thermal hold,
a weak source). The cable is in and the wall is paying; treating it as battery
would stop work on a charging desk overnight — the exact case background work
exists for.

## Concurrency

| Event | Mode | Why |
|---|---|---|
| `InitializePowerEvent` | `droppable` | initializing twice would double-subscribe and start a second poll timer whose handle overwrites the first, leaking past `close()` |
| `PowerChangedEvent` | `sequential` | it reads state, compares, and emits — a read-modify-write that is atomic today only because `execute` never awaits. `sequential` makes that structural rather than incidental |
| `CheckPowerEvent` | `droppable` | a poll tick and a manual check can coincide; the second platform read reports the same instant |

## Rebuild groups

| Group | Emitted when |
|---|---|
| `power:source` | `status` changed |
| `power:level` | `percent` changed |
| `power:saver` | `saverOn` changed |

`PowerChangedUseCase` emits **only** the groups that moved, and returns without
emitting when nothing did — the poll fires every minute and most reads find
nothing new.

## Lifecycle

`close()` cancels the poll timer, cancels the provider subscription, and
disposes the provider before `super.close()`. A surviving `Timer.periodic`
would re-enter a closed bloc; the test suite asserts no reads occur after
close.

## Out of scope

**Thermal state.** The other legitimate reason to back off expensive work, and
deliberately absent: no package in this family ships native code, and
`ProcessInfo.thermalState` has no cross-platform Flutter source. Adding it here
would make every consumer of a battery bloc take a platform dependency. An app
that needs it can add a channel and combine it with this state — the seam makes
that composition natural rather than a fork.

**Charge prediction / time remaining.** Platform estimates are unreliable and
consumers that want them can compute from `percent` over time.

## Testing

Headless, with a fake `PowerProvider`. Every transition — unplug, saver toggle,
level drift with no status change, a level going unknown, close-during-poll —
is a one-line push. 18 tests; `flutter analyze` clean.
