# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.0] - 2026-10-14

### Changed

- **Requires `juice ^2.0.0`.** Provider changes are a bloc-owned stream binding
  (`bindStream(..., key: 'changes')`): no `StreamSubscription` field, no
  `isClosed` guard, no manual cancel in `close()` — the bloc cancels it before
  the use cases close, and a second start replaces the binding instead of
  leaking it. A stream error now reaches the bloc's error handler (logged as
  `stream_binding/error` and `bloc_error`) and the binding keeps listening, as
  the old subscription did; before, the error was uncaught.
- `close()` closes the bloc first (its binding is cancelled), then disposes the
  provider; a dispose failure is logged, never swallowed; an uninitialised bloc
  closes cleanly; a second `close()` awaits the first (the provider is disposed
  once).
- `startPolling` cancels the previous poll timer before starting another.
- `provider` / `config` before `InitializePowerEvent` throw a named `StateError`
  instead of a late-initialisation error.
- A second `InitializePowerEvent` after the first completed is refused with a
  `StateError` through the use case's error path (logged as `use_case_error` and
  `bloc_error`); the bloc owns one provider for its life, and the first stays
  live. Before, the config was silently replaced and the first provider never
  disposed.
- **`battery_plus` `>=6.2.0 <8.0.0`** (was `^6.2.0`): an app on battery_plus 7
  can resolve this package. The default provider compiles and its tests pass at
  both ends of the range; the new major has not had an on-device run yet.

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
