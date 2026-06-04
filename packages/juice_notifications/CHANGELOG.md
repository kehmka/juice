# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
