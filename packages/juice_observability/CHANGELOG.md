# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2026-05-28

### Added

- Initial release.
- **`ObservabilityBloc`** — crash reporting + breadcrumbs, fanned out to one or
  more reporters.
- **Global capture** — installs `FlutterError.onError` +
  `PlatformDispatcher.onError` (chaining any existing handlers; restored on
  `close`) so uncaught errors are reported automatically.
- **`CrashReporter`** — vendor seam (`recordError`/`addBreadcrumb`/`setUser`/
  `setContext`). Ship a Sentry/Crashlytics adapter; `ConsoleCrashReporter` and
  `NoopCrashReporter` included.
- **Breadcrumb ring** — bounded trail (`maxBreadcrumbs`) attached to each report.
- **Fan-out with isolation** — a throwing reporter can't break the others.
- **API** — `recordError`, `breadcrumb`, `setUser`, `setContext`, `setEnabled`.
- **Rebuild group** — `observability:status`.
