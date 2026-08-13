# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.3.0] - 2026-08-12

### Changed

- Require `juice ^1.6.0`.
- Declare initialization and opening app settings `droppable`.
- Keep status checks and individual permission requests intentionally
  `concurrent`; checks merge at emit time, while requests retain
  per-permission singleflight and allow different permissions to overlap.
- Run batch permission requests `sequential`ly so their shared `inFlight` and
  status mutations cannot interleave.

### Tests

- Add gated coverage for concurrent independent checks, concurrent distinct
  permission prompts, sequential batch prompts, and duplicate Settings-open
  coalescing.

## [0.2.0] - 2026-05-28

### Added
- **`PermissionBinding`** — a generic, callback-based binding from
  `PermissionsBloc` to anything that cares about one permission's status. This is
  how capability blocs (notifications/location/media) react to permission
  changes, without per-capability glue packages. Depends only on
  `juice_permissions` (the callback decouples it from the capability bloc).

## [0.1.0] - 2026-05-28

### Added

- Initial release.
- **`PermissionsBloc`** — owns the grant-state machine for each runtime permission.
- **`JuicePermission`** — vendor-agnostic enum covering the full
  `permission_handler` set (camera, location, media, notifications, bluetooth, …).
- **`PermissionProvider`** — vendor seam; the bloc depends on this, not on a
  platform plugin, so it is testable without a device.
- **`PermissionHandlerProvider`** — default provider backed by `permission_handler`.
- **Per-permission singleflight** — concurrent requests collapse to one OS prompt.
- **`isGranted` / `isUsable`** — strict vs. usable (granted | limited | provisional).
- **Rebuild groups** — `permissions:status`, per-permission `permissions:status:<name>`,
  and `permissions:inflight`.
