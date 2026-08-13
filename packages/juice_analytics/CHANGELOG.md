# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.0] - 2026-08-12

### Changed

- **Requires `juice ^1.6.0`.**
- Declared concurrency for every event. Logging, screen, user, and consent
  changes are `sequential`, preserving vendor-call and state order across
  awaits. Initialization and flush are `droppable`, preventing overlapping
  ownership changes and redundant sink flushes.

## [0.1.0] - 2026-05-28

### Added

- Initial release.
- **`AnalyticsBloc`** — event + screen tracking, fanned out to one or more
  sinks, behind a **consent gate**.
- **`AnalyticsSink`** — vendor seam (`logEvent`/`setScreen`/`setUser`/`flush`).
  Ship a Firebase/Mixpanel/Segment adapter; `ConsoleAnalyticsSink` and
  `NoopAnalyticsSink` included.
- **Fan-out with isolation** — a throwing sink can't break tracking for the rest.
- **Consent-first** — when disabled, events are **dropped (counted)**, never
  buffered, so nothing leaks once consent is later granted.
- **API** — `log`, `screen`, `setUser`, `setConsent`, `flush`.
- **Rebuild groups** — `analytics:status`, `analytics:screen`.
