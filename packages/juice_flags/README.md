# juice_flags

Feature flags / remote config as a [Juice](https://pub.dev/packages/juice) bloc —
behind a swappable source seam, with **per-flag selective rebuilds**.

[![pub package](https://img.shields.io/pub/v/juice_flags.svg)](https://pub.dev/packages/juice_flags)
[![License: MIT](https://img.shields.io/badge/license-MIT-purple.svg)](LICENSE)

## What it owns

The resolved value of each flag. It does **not** own *where* values come from —
that's a `FlagsSource` (Firebase Remote Config, LaunchDarkly, an endpoint, a
local map). The bloc never depends on a vendor SDK.

## Install

```yaml
dependencies:
  juice_flags: ^0.1.0
```

## Use

```dart
final flags = FlagsBloc.withConfig(FlagsConfig(
  defaults: {'new_checkout': false, 'max_items': 20}, // safe baseline
));

if (flags.boolFlag('new_checkout')) showNewCheckout();
```

Reads always resolve to *something* (a flag can't render "unknown"):
`boolFlag`, `stringFlag`, `intFlag`, `doubleFlag`, `json<T>` — each with a
fallback. Values resolve in layers: **`defaults < fetched < overrides`**.

## Per-flag selective rebuild

Each flag owns a rebuild group. On a fetch the bloc **diffs old vs new and emits
only the flags that changed** — so a refresh touching 2 of 50 flags rebuilds
only those 2 widgets.

```dart
class Checkout extends StatelessJuiceWidget<FlagsBloc> {
  Checkout({super.key}) : super(groups: {FlagsGroups.flag('new_checkout')});

  @override
  Widget onBuild(BuildContext context, StreamStatus status) =>
      bloc.boolFlag('new_checkout') ? const NewCheckout() : const OldCheckout();
}
```

## Firebase Remote Config (or any vendor)

The bloc stays vendor-free; Firebase is just a `FlagsSource` you write in your
app (or publish as an adapter package later):

```dart
class FirebaseRemoteConfigFlagsSource implements FlagsSource {
  final FirebaseRemoteConfig _rc;
  FirebaseRemoteConfigFlagsSource(this._rc);

  @override
  Future<Map<String, Object?>> fetch() async {
    await _rc.fetchAndActivate();
    return _rc.getAll().map((k, v) => MapEntry(k, _coerce(v)));
  }

  Object? _coerce(RemoteConfigValue v) {
    final s = v.asString();
    if (s == 'true' || s == 'false') return s == 'true';
    return num.tryParse(s) ?? s; // JSON stays a string → decode via bloc.json()
  }

  @override
  Stream<Map<String, Object?>>? changes() => _rc.onConfigUpdated.asyncMap((_) async {
    await _rc.activate();
    return _rc.getAll().map((k, v) => MapEntry(k, _coerce(v)));
  });

  @override
  Future<void> dispose() async {}
}

final flags = FlagsBloc.withConfig(FlagsConfig(
  source: FirebaseRemoteConfigFlagsSource(FirebaseRemoteConfig.instance),
  defaults: {'new_checkout': false},
));
```

## Fetch is fail-loud but read-safe

A failed fetch surfaces in `state.error` (and is logged) — never swallowed. But
flag *reads* keep returning last-known/defaults, because a flag must always
resolve to a value. Defaults are the floor; the source only raises confidence.

## Overrides (dev toggles)

```dart
flags.setFlagOverride('new_checkout', true);  // wins over fetched
flags.clearFlagOverride('new_checkout');       // revert
```

## State

| Field | Meaning |
|---|---|
| `values` | resolved map (defaults overlaid by fetched + overrides) |
| `loading` | a fetch is in flight |
| `fetched` | at least one successful fetch |
| `error` | last fetch error (reads stay safe) |

Rebuild groups: `FlagsGroups.flag(key)`, `FlagsGroups.any`, `FlagsGroups.status`.

## License

MIT License — see [LICENSE](LICENSE).
