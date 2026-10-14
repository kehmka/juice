# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.3.0] - unreleased (ships with juice 2.0.0)

### Changed

- Require `juice ^2.0.0`. Position tracking is a bloc-owned stream binding
  (`bindStream(..., key: 'tracking')` / `unbind('tracking')`): no
  `StreamSubscription` field, no `isClosed` guard, no manual cancel in `close()`
  — the bloc cancels it before the use cases close. A second
  `StartTrackingEvent` replaces the first binding instead of leaking it.
- `close()` closes the bloc first (its tracking binding is cancelled) and
  disposes the source after; a dispose failure is logged, never swallowed; an
  uninitialised bloc closes cleanly; a second `close()` awaits the first (the
  source is disposed once).
- A positions stream that errors or ends on its own ends tracking:
  `TrackingEndedEvent` sets `tracking: false` (and `lastError` on an error, on
  the `error` group). Before, the state kept saying `tracking: true`.
- `source` / `config` before `InitializeLocationEvent` throw a named
  `StateError` instead of a late-initialisation error.

## [0.2.0] - 2026-08-12

### Changed

- Require `juice ^1.6.0` and declare an explicit concurrency policy for every
  event.
- Coalesce overlapping initialization and one-shot location reads with
  `EventConcurrency.droppable`.
- Process tracking state, position updates, and permission changes
  sequentially to preserve event order.

## [0.1.0] - 2026-05-28

### Added

- Initial release.
- **`LocationBloc`** — one-shot reads and continuous position tracking.
- **`LocationSource`** — vendor seam; the bloc depends on this, not on a plugin,
  so it is testable without a device.
- **`GeolocatorLocationSource`** — default backed by `geolocator`.
- **`GeoPosition`** — vendor-agnostic position (lat/lng/accuracy/altitude/speed/heading).
- **`setPermissionStatus`** — neutral permission entry point; wire from
  `juice_permissions` with a `PermissionBinding` (no `juice_permissions` dep here).
- **Rebuild groups** — `location:position`, `location:tracking`,
  `location:permission`, `location:error`.
