# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
