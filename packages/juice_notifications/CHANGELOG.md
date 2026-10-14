# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.3.0] - unreleased (ships with juice 2.0.0)

### Changed

- **Requires `juice ^2.0.0`.** Service taps are a bloc-owned stream binding
  (`bindStream(..., key: 'taps')`): no `StreamSubscription` field, no `isClosed`
  guard, no manual cancel in `close()` — the bloc cancels it before the use
  cases close, and a second start replaces the binding instead of leaking it. A
  stream error now reaches the bloc's error handler (logged as
  `stream_binding/error` and `bloc_error`) and the binding keeps listening, as
  the old subscription did; before, the error was uncaught.
- `close()` closes the bloc first (its binding is cancelled), then disposes the
  service; a dispose failure is logged, never swallowed; an uninitialised bloc
  closes cleanly; a second `close()` awaits the first (the service is disposed
  once).
- `service` / `config` before `InitializeNotificationsEvent` throw a named
  `StateError` instead of a late-initialisation error.
- A second `InitializeNotificationsEvent` after the first completed is refused
  with a `StateError` through the use case's error path (logged as
  `use_case_error` and `bloc_error`); the bloc owns one service for its life,
  and the first stays live. Before, the config was silently replaced and the
  first service never disposed.
- `close()` waits for a service operation still in flight (a schedule, a cancel)
  before disposing the service.

## [0.2.0] - 2026-08-12

### Changed

- Require `juice ^1.6.0` and declare an explicit concurrency policy for every
  event.
- Serialize initialization, show, schedule, cancel, and cancel-all through one
  cross-event FIFO so platform side effects and tracked state retain send order.
- Process tap and permission updates sequentially.

## [0.1.1] - 2026-05-28

### Fixed

- `NotificationsState.copyWith` can now clear `lastTap` (added the `_unset`
  sentinel) — previously passing `null` silently preserved the old tap.

## [0.1.0] - 2026-05-28

### Added

- Initial release (local-first).
- **`NotificationsBloc`** — local notification delivery, scheduling, and tap routing.
- **`NotificationService`** — vendor seam; the bloc depends on this, not on a
  plugin, so it is testable without a device.
- **`LocalNotificationService`** — default backed by `flutter_local_notifications`
  (+ `timezone` for scheduling).
- **`setPermissionStatus`** — neutral permission entry point; wire from
  `juice_permissions` with a `PermissionBinding` (no `juice_permissions` dep here).
- **Rebuild groups** — `notifications:scheduled`, `notifications:tap`,
  `notifications:permission`.

### Out of scope

- Push notifications (FCM/APNs) — a separate `PushNotificationSource` seam is planned.
