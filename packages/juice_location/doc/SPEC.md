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

| Event | Effect | Groups |
|-------|--------|--------|
| `InitializeLocationEvent(config)` | store config | — |
| `GetCurrentLocationEvent` | one-shot read (→ `LocationChanged`, or error) | `location:position` / `location:error` |
| `StartTrackingEvent` | subscribe to `positions()` | `location:tracking` |
| `StopTrackingEvent` | cancel subscription | `location:tracking` |
| `LocationChangedEvent` | internal — record position | `location:position` |
| `SetPermissionStatusEvent(granted)` | record permission (from `PermissionBinding`) | `location:permission` |

The bloc owns the tracking `StreamSubscription` (started in `startTracking`,
cancelled in `stopTracking` and `close`).

## Testing

Headless with a fake `LocationSource`: one-shot read, error surfacing, tracking
start/stop (no updates after stop), permission flag, dispose. The device-touching
`GeolocatorLocationSource` is verified by inspection + one on-device run.

## Spec Version

| Version | Date | Status |
|---------|------|--------|
| 1.0 | 2026-05-28 | Implemented |
