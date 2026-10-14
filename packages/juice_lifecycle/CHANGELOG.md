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
- `provider` / `config` before `InitializeLifecycleEvent` throw a named
  `StateError` instead of a late-initialisation error.

## [0.2.0] - 2026-08-12

### Changed

- Require `juice ^1.6.0` and declare an explicit concurrency policy for every
  event.
- Coalesce overlapping initialization with `EventConcurrency.droppable`.
- Process lifecycle transitions sequentially so `previous` always reflects
  provider stream order, including rapid bursts.

## [0.1.0] - 2026-05-28

### Added

- Initial release.
- **`LifecycleBloc`** — owns the app's foreground/background/resume phase.
- **`LifecycleProvider`** — vendor seam; the bloc depends on this, not on
  `WidgetsBinding`, so it is testable without a real binding.
- **`WidgetsLifecycleProvider`** — default provider backed by Flutter's
  `AppLifecycleListener`.
- **Convenience getters** — `isForeground`, `isBackground`, `resumedFromBackground`,
  plus `previous` phase.
- **Rebuild group** — `lifecycle:state`.
