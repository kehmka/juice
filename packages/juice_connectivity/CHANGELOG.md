# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.3.0] - unreleased (ships with juice 2.0.0)

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
- `provider` / `config` before `InitializeConnectivityEvent` throw a named
  `StateError` instead of a late-initialisation error.
- A second `InitializeConnectivityEvent` after the first completed is refused
  with a `StateError` through the use case's error path (logged as
  `use_case_error` and `bloc_error`); the bloc owns one provider for its life,
  and the first stays live. Before, the config was silently replaced and the
  first provider never disposed.
- **`connectivity_plus` `>=6.1.0 <8.0.0`** (was `^6.1.0`): an app on
  connectivity_plus 7 can resolve this package. The default provider compiles
  and its tests pass at both ends of the range; the new major has not had an on-
  device run yet.

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
