# juice_power

Battery and charging state as a [Juice](https://pub.dev/packages/juice) bloc —
plugged-in, charge level and power-saver mode behind a swappable provider seam.

[![pub package](https://img.shields.io/pub/v/juice_power.svg)](https://pub.dev/packages/juice_power)
[![License: MIT](https://img.shields.io/badge/license-MIT-purple.svg)](LICENSE)

## What it owns

The device's power situation: whether external power is connected, how much
charge remains, and whether the OS power saver is on (iOS Low Power Mode,
Android Battery Saver).

It does **not** decide what to do about any of that. Whether your expensive
work may run on battery — and below what percentage — is *your* policy, because
only you know how expensive the work is and how badly the user wants it. This
bloc reports; consumers decide.

## Install

```yaml
dependencies:
  juice_power: ^0.1.0     # pulls battery_plus for the default provider
```

## Use

```dart
import 'package:juice/juice.dart';
import 'package:juice_power/juice_power.dart';

final power = PowerBloc.withConfig(PowerConfig());

class ChargeBadge extends StatelessJuiceWidget<PowerBloc> {
  ChargeBadge({super.key}) : super(groups: {PowerGroups.source, PowerGroups.level});

  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    final s = bloc.state;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(s.isPluggedIn ? Icons.power : Icons.battery_std),
      Text(s.percent == null ? '—' : '${s.percent}%'),
    ]);
  }
}
```

The usual reason to reach for this package is gating expensive background work.
Express that as a relay, not a listener:

```dart
// Stop when the cable comes out; start again when it goes back in.
StateRelay<PowerBloc, WellBloc, PowerState>(
  toEvent: (_) => PauseWellEvent(),
  when: (s) => s.oldState.isPluggedIn && !s.state.isPluggedIn,
);
StateRelay<PowerBloc, WellBloc, PowerState>(
  toEvent: (_) => ResumeWellEvent(),
  when: (s) => !s.oldState.isPluggedIn && s.state.isPluggedIn,
);
```

## Three values that can be unknown

Platforms lie, decline, and throw. This package reports *unknown* as unknown
rather than substituting a plausible number, because every guess here is wrong
in a direction that matters:

| Reading | Unknown when | Why it is not guessed |
|---|---|---|
| `status` | before the first read; platform says so | `isPluggedIn` is **false** for `unknown` — "may I burn power?" must answer no until something says yes |
| `percent` | Simulator (-1); some devices throw | `isAtOrBelow(20)` returns **false** on unknown. A fabricated `0` would slam every gate shut on a full battery |
| `saverOn` | platform throws | `false` is the *permissive* answer — guessing it silently grants permission to burn power on a device that was asking to stop |

`PowerState.saverAsked` gives you the reading most consumers want (`true` only
when the user positively asked to conserve) — but as a choice made in the open,
next to the work it affects, rather than one buried in a provider.

## Why the level is polled

Platforms broadcast plugged/unplugged promptly and the percentage hardly at
all. Without polling, a consumer gating on "below 20%" would act on a number
frozen at the last time a cable moved. `PowerConfig.pollInterval` defaults to
one minute — far finer than a battery moves, one cheap platform call. Set it to
`Duration.zero` if you only care whether power is connected.

## The provider seam (and why it's testable)

`PowerBloc` depends on the `PowerProvider` interface, not on a platform plugin.
The shipped `BatteryPlusProvider` is one implementation; in tests you inject a
fake and drive every transition — unplugged, saver on, charge crossing a
threshold — in a line each, with no device:

```dart
final fake = FakePowerProvider();
final bloc = PowerBloc.withConfig(PowerConfig(provider: fake, pollInterval: Duration.zero));

fake.emit(const PowerSnapshot(status: BatteryStatus.discharging, percent: 12));
```

## Rebuild groups

| Group | Emitted when |
|---|---|
| `power:source` | plugged in or unplugged |
| `power:level` | the charge level moved |
| `power:saver` | the OS power saver was switched on or off |

A reading that changes nothing emits nothing — the poll would otherwise wake
every consumer once a minute for a number that had not moved.

## What it deliberately leaves out

**Thermal state.** A hot phone is the other reason to back off expensive work,
and `ProcessInfo.thermalState` / Android's thermal API would answer it — but no
package in this family ships native code, and adding it here would make every
consumer of a battery bloc take a platform dependency. If you need thermal
throttling, put a small channel in your app and combine it with this state.

## License

MIT
