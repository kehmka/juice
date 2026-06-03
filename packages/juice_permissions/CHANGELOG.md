# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
