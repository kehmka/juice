---
card_schema: "1.0"
package: juice_flags
version: 0.1.0
requires:
  juice: ">=1.4.0"
updated: 2026-06-09
---

# juice_flags — AI card

> Feature flags / remote config as a bloc: resolve values in layers
> (`defaults < fetched < overrides`) behind a swappable source seam, with
> **per-flag selective rebuilds**. Read repo `AGENTS.md` for the Juice mental
> model + gotchas.

## Purpose

**Owns:** the resolved value of each flag + fetch status.
**Does NOT own:** *where* values come from (the `FlagsSource` seam) or the vendor
SDK — a remote source is a provider impl behind the seam, not a glue package.

## When to use

Feature gating / remote config / dev toggles where you want flags to always
resolve to a safe value, route to any provider (Firebase Remote Config,
LaunchDarkly, an endpoint, a local map), and rebuild only the widgets whose flag
actually changed.

## Install

```yaml
dependencies:
  juice_flags: ^0.1.0
```

## Construct

No required seam — defaults to an empty `StaticFlagsSource`. `withConfig`
initializes (seeds defaults, subscribes to `changes()`, optional first fetch):

```dart
final flags = FlagsBloc.withConfig(FlagsConfig(
  source: FirebaseRemoteConfigFlagsSource(FirebaseRemoteConfig.instance),
  defaults: {'new_checkout': false, 'max_items': 20},  // floor; flags always resolve
  fetchOnInit: true,
));
if (flags.boolFlag('new_checkout')) showNewCheckout();
```

## Seams

```dart
// Vendor seam. Values are vendor-agnostic: bool / num / String / JSON-decodable.
// Default StaticFlagsSource (in-memory, pull-only).
abstract class FlagsSource {
  Future<Map<String, Object?>> fetch();        // pull all values
  Stream<Map<String, Object?>>? changes();     // live updates, or null if pull-only
  Future<void> dispose();
}
```

## API

```dart
// Typed reads — always resolve to something (fallback if absent/wrong type):
bool boolFlag(String key, {bool fallback = false});
String stringFlag(String key, {String fallback = ''});
int intFlag(String key, {int fallback = 0});      // coerces num
double doubleFlag(String key, {double fallback = 0}); // coerces num
T? json<T>(String key);                            // structured; null if absent/wrong type

// Commands:
void refresh();
void setFlagOverride(String key, Object? value);   // wins over fetched
void clearFlagOverride(String key);
```

## Events

| Event | Effect |
|---|---|
| `InitializeFlagsEvent(config)` | seed defaults, subscribe to `changes()`, optional first fetch |
| `RefreshFlagsEvent` | pull from source, emit only changed flags |
| `FlagsUpdatedEvent(values)` *internal* | live-stream values arrived → diff + emit changed |
| `FlagsFetchFailedEvent(error)` *internal* | live-stream error → `emitFailure`, values intact |
| `SetFlagOverrideEvent(key, value)` | apply local override (wins) |
| `ClearFlagOverrideEvent(key)` | revert to fetched/default |

## State

```dart
class FlagsState {            // BlocState
  Map<String, Object?> values; // RESOLVED map (defaults < fetched < overrides)
  bool loading;                // fetch in flight
  String? error;               // last fetch error; reads still fall back to last-known
  bool fetched;                // at least one successful fetch
}
```

Read via the typed accessors, not `state.values[key]` directly (the accessors
apply type-safe fallbacks).

## Rebuild groups

| Group | Emitted when |
|---|---|
| `FlagsGroups.flag(key)` → `flags:flag:<key>` | **that flag's** resolved value changed (dynamic per-key) |
| `FlagsGroups.any` → `flags:any` | any flag changed |
| `FlagsGroups.status` → `flags:status` | fetch lifecycle (loading / error / fetched) changed |

`FlagsGroups.all = {any, status}` (per-flag groups are dynamic — reach via
`flag(key)`). On every fetch / stream push / override, the bloc computes
`changedKeys(old, new)` and emits only those flags' groups — a refresh touching
2 of 50 flags rebuilds only 2 widgets.

## Recipes

```dart
// 1. Remote source adapter (Firebase Remote Config shown)
class FirebaseRemoteConfigFlagsSource implements FlagsSource {
  FirebaseRemoteConfigFlagsSource(this._rc);
  final FirebaseRemoteConfig _rc;
  @override Future<Map<String, Object?>> fetch() async {
    await _rc.fetchAndActivate();
    return {for (final e in _rc.getAll().entries) e.key: e.value.asString()};
  }
  @override Stream<Map<String, Object?>>? changes() =>
      _rc.onConfigUpdated.asyncMap((_) => fetch());
  @override Future<void> dispose() async {}
}

// 2. Per-flag widget — rebuilds ONLY when this flag changes
class CheckoutGate extends StatelessJuiceWidget<FlagsBloc> {
  CheckoutGate({super.key}) : super(groups: {FlagsGroups.flag('new_checkout')});
  @override Widget onBuild(BuildContext c, StreamStatus s) =>
      bloc.boolFlag('new_checkout') ? const NewCheckout() : const OldCheckout();
}

// 3. Dev override panel
flags.setFlagOverride('new_checkout', true);   // wins until cleared
flags.clearFlagOverride('new_checkout');
```

## Testing

Headless with a fake/static source; assert diff-on-fetch via group emissions:

```dart
final source = StaticFlagsSource({'a': 1, 'b': 2});
final bloc = FlagsBloc.withConfig(FlagsConfig(
    source: source, defaults: {'a': 0, 'b': 0, 'c': 9}, fetchOnInit: true));
await settle();                       // Future.delayed(20ms)
expect(bloc.intFlag('a'), 1);         // fetched overlays default
expect(bloc.intFlag('c'), 9);         // default floor (not in source)
bloc.setFlagOverride('a', 99);
await settle();
expect(bloc.intFlag('a'), 99);        // override wins
```

## Failure modes

- A failed `fetch()` (or live-stream error) → `emitFailure` sets `state.error`
  and `loading=false`, but **leaves resolved values intact** — reads keep
  returning last-known/defaults. This is the one legitimate, *loud* fallback:
  error visible, values safe.
- `changedKeys` empty → no emit (an update that changes nothing is a no-op).
- `close()` cancels the changes subscription and disposes the source.

## Anti-patterns

- ❌ Reading `state.values[key]` directly — use `boolFlag`/`intFlag`/… so a
  missing/wrong-type value falls back instead of returning `null`/crashing.
- ❌ Treating a failed fetch as "no flags" — values persist; check `state.error`
  for the failure, not an empty map.
- ❌ Binding a widget to `FlagsGroups.any` when it reads one flag — use
  `FlagsGroups.flag(key)` for minimal rebuilds.
- ❌ Building a vendor-shaped bloc or glue package for a provider — a source is a
  plain `FlagsSource` impl behind the seam.

## Invariants

- **Layered resolution:** `defaults < fetched < overrides`; a flag always
  resolves (defaults are the floor).
- **Diff-on-change:** only flags whose resolved value differs emit their group.
- **Read-safe under failure:** a fetch error never clears resolved values.

## See also

`SPEC.md` (resolution/selective-refresh) · `README.md` (narrative) · repo
`AGENTS.md` (framework).
