# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.0] - 2026-09-15

### Changed — behaviour, not cleanup (ISSUES #22)
- Requires `juice: ^1.6.0`. Every `UseCaseBuilder` now declares an
  `EventConcurrency` mode: `InitializeThemeEvent` → `droppable`;
  `SetThemeModeEvent`, `ToggleThemeEvent`, `SetFlavorEvent` → `sequential`.
  `commit` already emitted state synchronously before awaiting `save`, so
  state was race-free; what `sequential` adds is that SAVES complete in the
  order the selections were made, so persistence can never end up holding an
  older selection than state (and load the wrong theme next launch). The
  property that comes with it, stated plainly: `sequential` queues the WHOLE
  use case, so a second change's emit waits behind the previous change's
  `save` (milliseconds with `StorageThemePersistence`; visible only behind a
  slow custom persistence). The test pins exactly that.
- Known, documented: modes are keyed by exact event type — `ToggleThemeEvent`
  and `SetThemeModeEvent` both write `mode` and are not serialized against
  each other. Stakes are a stale theme on next launch; a bloc-owned persist
  tail would close it, deferred.

### Tests
- Gated-persistence coverage: overlapping initializations coalesce to one
  `load`; a second mode change's `save` does not start until the first
  completes.

## [0.1.1] - 2026-06-16

### Changed
- Allow `juice_storage` 2.0.0 (Hive CE migration). No API change.

## [0.1.0] - 2026-05-28

### Added

- Initial release.
- **`ThemeBloc`** — owns the theme selection: `ThemeMode` + optional named flavor.
- **`ThemePersistence`** — vendor seam; the bloc depends on this, not on storage,
  so it is testable without real storage.
- **`StorageThemePersistence`** — default persistence backed by `StorageBloc`
  (SharedPreferences). Pass `null` for in-memory-only.
- **Convenience** — `setMode`, `toggle` (light⇄dark), `setFlavor`; getters
  `isDarkMode` / `isLightMode` / `isSystemMode`.
- **Rebuild groups** — `theme:mode`, `theme:flavor`.
