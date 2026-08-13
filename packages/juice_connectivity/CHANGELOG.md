# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.0] - 2026-08-12

### Changed

- **Requires `juice ^1.6.0`.**
- Declared concurrency for every event: initialization and manual checks are
  `droppable`, while connectivity changes are `sequential`. This prevents
  duplicate subscriptions and redundant provider reads, and makes ordered
  state mutation structural rather than dependent on the current synchronous
  implementation.

## [0.1.0] - 2026-05-28

### Added

- Initial release.
- **`ConnectivityBloc`** — owns online/offline status and active connection type.
- **`ConnectivityProvider`** — vendor seam; the bloc depends on this, not on a
  platform plugin, so it is testable without a device.
- **`ConnectivityPlusProvider`** — default provider backed by `connectivity_plus`.
- **Debounce** — configurable quiet period to absorb network flapping.
- **Rebuild groups** — `connectivity:status`, `connectivity:type`.
