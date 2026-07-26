# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2026-07-25

### Added

- Initial release.
- **`PowerBloc`** — owns the device's power situation: charging status, charge
  level, and OS power-saver mode.
- **`PowerProvider`** — vendor seam; the bloc depends on this, not on a platform
  plugin, so every transition is testable without a device.
- **`BatteryPlusProvider`** — default provider backed by `battery_plus`.
- **Level polling** — configurable `pollInterval` (default 1 minute), because
  platforms broadcast plugged/unplugged but not the percentage; `Duration.zero`
  disables it.
- **Unknown is reported as unknown** — `percent` and `saverOn` are nullable and
  the provider logs rather than substituting a plausible value; `isPluggedIn` is
  false for `unknown` status, and `isAtOrBelow` refuses to compare against an
  unknown level.
- **Rebuild groups** — `power:source`, `power:level`, `power:saver`, emitted
  only for what actually changed.
