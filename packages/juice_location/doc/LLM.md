---
card_schema: "1.0"
package: juice_location
version: 0.1.0
requires:
  juice: ">=1.4.0"
  geolocator: ">=13.0.0"
updated: 2026-06-09
---

# juice_location — AI card

> Device location (one-shot + continuous tracking) as a Juice bloc, behind a
> swappable `LocationSource` seam. Read repo `AGENTS.md` for the Juice mental
> model + gotchas.

## Purpose

**Owns:** current `GeoPosition`, tracking on/off, an informational
`permissionGranted` flag, last error.
**Does NOT own:** the permission grant (`juice_permissions` via
`PermissionBinding`), maps, or geocoding.

## Install

```yaml
dependencies:
  juice_location: ^0.1.0
```

Default source is `geolocator` — add its platform setup (iOS
`NSLocationWhenInUseUsageDescription`; Android `ACCESS_FINE_LOCATION` /
`ACCESS_COARSE_LOCATION`).

## Construct

`source` defaults to `GeolocatorLocationSource`.

```dart
final location = LocationBloc.withConfig(LocationConfig(
  source: GeolocatorLocationSource(),    // optional; this is the default
));
location.getCurrent();      // one-shot
location.startTrackingUpdates();  // continuous
```

## Seams

```dart
abstract class LocationSource {
  Future<GeoPosition> current();        // one-shot fix
  Stream<GeoPosition> positions();      // continuous (subscribed while tracking)
  Future<void> dispose();
}
// GeoPosition: latitude, longitude, accuracy(m), altitude, speed(m/s), heading, timestamp
```

## API

```dart
void getCurrent();                 // one-shot read
void startTrackingUpdates();       // subscribe to positions()
void stopTrackingUpdates();        // cancel subscription
void setPermissionStatus(bool granted);  // wire from juice_permissions
```

## Events

| Event | Effect | Group |
|---|---|---|
| `InitializeLocationEvent(config)` | store config | — |
| `GetCurrentLocationEvent` | one-shot read → `LocationChanged`, or error | `position` / `error` |
| `StartTrackingEvent` | subscribe to `positions()` (no-op if tracking) | `tracking` |
| `StopTrackingEvent` | cancel subscription (no-op if not tracking) | `tracking` |
| `LocationChangedEvent(pos)` *internal* | record position; clears error | `position` |
| `SetPermissionStatusEvent(bool)` | record permission flag | `permission` |

## State

```dart
class LocationState extends BlocState {
  GeoPosition? current;        // null before first fix
  bool tracking;
  bool permissionGranted;      // informational; OS is final authority
  String? lastError;
}
```

## Rebuild groups

| Group | Emitted when |
|---|---|
| `LocationGroups.position` → `location:position` | current position changed |
| `LocationGroups.tracking` → `location:tracking` | tracking started/stopped |
| `LocationGroups.permission` → `location:permission` | permission flag changed |
| `LocationGroups.error` → `location:error` | a read failed |

## Recipes

```dart
// 1. Show the current position (selective)
class PositionLabel extends StatelessJuiceWidget<LocationBloc> {
  PositionLabel() : super(groups: {LocationGroups.position});
  @override Widget onBuild(BuildContext c, StreamStatus s) {
    final p = bloc.state.current;
    return Text(p == null ? '—' : '${p.latitude}, ${p.longitude}');
  }
}

// 2. Custom source (fake / non-default backend)
class FakeSource implements LocationSource {
  final _stream = StreamController<GeoPosition>.broadcast();
  GeoPosition? oneShot;
  Future<GeoPosition> current() async => oneShot ?? (throw 'no fix');
  Stream<GeoPosition> positions() => _stream.stream;
  Future<void> dispose() async => _stream.close();
  void emit(GeoPosition p) => _stream.add(p);
}
```

## Testing

Headless — fake the source, drive the bloc:

```dart
final src = FakeSource();
final loc = LocationBloc.withConfig(LocationConfig(source: src));
loc.startTrackingUpdates();
await settle();                              // Future.delayed(20ms)
expect(loc.state.tracking, isTrue);
src.emit(GeoPosition(latitude: 1, longitude: 2, timestamp: DateTime.now()));
await settle();
expect(loc.state.current?.latitude, 1);
loc.stopTrackingUpdates();
await settle();
expect(loc.state.tracking, isFalse);         // no updates land after stop
```

## Failure modes

- `current()` throws → `emitFailure`, `lastError` set, `error` group (one-shot
  reads surface failures; never a silent empty position).
- Stream errors from `positions()` propagate from the source — wrap your source
  if you need them folded into `lastError`.

## Anti-patterns

- ❌ Treating `permissionGranted` as the real grant — it's an informational
  mirror; drive it from `juice_permissions`.
- ❌ Calling `getCurrent()` in a tight loop for continuous updates — use
  `startTrackingUpdates()`.
- ❌ Forgetting `stopTrackingUpdates()` — the GPS subscription stays live
  (battery). `close()` cancels it, but stop when the screen is gone.

## Integrates with

- **juice_permissions** — capability-tier; no glue package. Mirror the grant:
  ```dart
  PermissionBinding(permissions, JuicePermission.locationWhenInUse,
    onStatus: (s) => location.setPermissionStatus(s == PermissionStatus.granted))..start();
  ```

## Invariants

- `StartTracking`/`StopTracking` are idempotent (early-return if already in the
  target state).
- A new position (one-shot or stream) clears `lastError`.
- `close()` cancels the tracking subscription and disposes the source.

## See also

`SPEC.md` (design depth) · `README.md` (narrative) · repo `AGENTS.md` (framework).
</content>
