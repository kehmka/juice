# juice_location Specification

> **Status:** Implemented (shipping).
> **Package:** `juice_location`
> **Primary Bloc:** `LocationBloc`

## Overview

A **capability-tier** bloc owning device location — one-shot reads and
continuous tracking. Uses the shared-permissions pattern: a neutral
`setPermissionStatus`, no `juice_permissions` dependency.

## Domain boundary

- **Owns:** current `GeoPosition`, tracking on/off, an informational
  `permissionGranted` flag, last error.
- **Does NOT own:** the permission grant (`juice_permissions` via
  `PermissionBinding`), maps, or geocoding.

## Dependencies

| Package | Why |
|---------|-----|
| `juice` | core bloc infrastructure |
| `geolocator` | default source backend |

No `juice_permissions` dependency — status arrives via `setPermissionStatus`.

## Seam

`LocationSource`: `current()` (one-shot), `positions()` (stream), `dispose()`.
Default `GeolocatorLocationSource`. `GeoPosition` is vendor-agnostic
(lat/lng/accuracy/altitude/speed/heading/timestamp).

## State

```dart
class LocationState extends BlocState {
  final GeoPosition? current;
  final bool tracking;
  final bool permissionGranted;   // set externally
  final String? lastError;
  static const initial = LocationState();
}
```

## Events

| Event | Concurrency | Effect | Groups |
|-------|-------------|--------|--------|
| `InitializeLocationEvent(config)` | `droppable` | store config | — |
| `GetCurrentLocationEvent` | `droppable` | one-shot read (→ `LocationChanged`, or error) | `location:position` / `location:error` |
| `StartTrackingEvent` | `sequential` | subscribe to `positions()` | `location:tracking` |
| `StopTrackingEvent` | `sequential` | cancel subscription | `location:tracking` |
| `LocationChangedEvent` | `sequential` | internal — record position | `location:position` |
| `SetPermissionStatusEvent(granted)` | `sequential` | record permission (from `PermissionBinding`) | `location:permission` |

One-shot reads are exclusive, preventing slower duplicate requests from
overwriting one another. State mutations retain event order.

The bloc owns the tracking `StreamSubscription` (started in `startTracking`,
cancelled in `stopTracking` and `close`).

## Testing

Headless with a fake `LocationSource`: one-shot read and in-flight coalescing,
error surfacing, ordered position bursts, tracking start/stop (no updates after
stop), permission flag, dispose. The device-touching
`GeolocatorLocationSource` is verified by inspection + one on-device run.

## Spec Version

| Version | Date | Status |
|---------|------|--------|
| 1.1 | 2026-08-12 | Juice 1.6 concurrency policy + overlap coverage |
| 1.0 | 2026-05-28 | Implemented |
