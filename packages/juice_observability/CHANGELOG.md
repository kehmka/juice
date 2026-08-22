# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.4.0] - 2026-08-21

### New Features

#### DevTools extension — Juice telemetry, visualized

Ships a DevTools extension (`extension/devtools/`) that consumes the
`juice:<type>` events `DevtoolsJuiceLogger` posts and renders four views:
**Timeline** (every transition, newest last), **Spans** (use-case
executions paired by `executionId` — honest durations even under
`concurrent` overlap, running/failed/elapsed), **Blocs** (per-bloc
emission count with the rebuild GROUPS each emission targeted — the
rebuild inspector groups make explainable), and **Problems** (errors,
unhandled events, leak detection). Loads automatically when a Juice app
using `DevtoolsJuiceLogger` connects to DevTools; a live-filter box and
clear across all four.

Source: `packages/juice_observability_devtools_extension` (`publish_to:
none`). The model is a pure `TelemetryModel` (7 unit tests, no VM); the
live `TelemetryStore` adds the VM wiring, split because
`devtools_extensions` is web-only.

## [0.3.1] - 2026-08-21

- Docs: README now actually introduces `DevtoolsJuiceLogger` (0.3.0's
  headline was missing from the pub.dev page) and the install snippet is
  current. Requires `juice ^1.7.0` so the span pairing documented here is
  structural, not aspirational.
- Example: demonstrates the mirror IN FULL — a Juice-pure `TelemetryFeedBloc`
  fed through the injectable `post` seam (teeing to the real VM post and an
  in-app panel), so every tap shows its `use_case_execution →
  use_case_completed` pair with `executionId` and elapsed time, no DevTools
  required. Teaches the self-loop guard (`isSelfTelemetry`): a bloc that
  consumes telemetry must filter out its own. Example tests cover the
  formatter, the guard, and a real start/end pair.

## [0.3.0] - 2026-08-21

### New Features

#### DevtoolsJuiceLogger — the framework's telemetry, live in DevTools

A `JuiceLogger` decorator that mirrors Juice's existing structured log
entries (use-case executions, state emissions, bloc lifecycle, event
subscriptions, unhandled events, leak detection, and all error types) to the
VM's extension-event stream via `dart:developer` `postEvent`, as
`juice:<type>` events — consumable live by DevTools and any VM-service
listener. A mirror on the existing logger seam, not new instrumentation:

- Typed entries (`context['type']`) post as `juice:<type>`; untyped chatter
  stays console-only; errors without a type always post as `juice:error`.
- Wire-safe payloads: primitives pass through; live objects (states, blocs,
  group sets) cross as `toString` capped at 512 chars.
- Decorates any inner logger (default `DefaultJuiceLogger`) — console
  logging keeps working; the `post` function is an injectable seam for
  tests.
- Phase 1 is instant events by design; duration spans await a
  `use_case_completed` entry in core (ROADMAP: BlocSignal tee-up, item 1).

One line to adopt: `JuiceLoggerConfig.configureLogger(DevtoolsJuiceLogger())`.

## [0.2.0] - 2026-06-09

### Changed

- **Requires `juice ^1.5.0`.**
- Adopt `EventConcurrency.sequential` for `RecordErrorEvent` and
  `AddBreadcrumbEvent`. The breadcrumb ring and error counter now live in state
  with a natural read-modify-write; the bloc-side accumulator workaround
  (`_breadcrumbs`/`_errorCount` + helpers) is removed. **Behavior unchanged** —
  rapid breadcrumbs/errors stay race-free, now via the framework mode.

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
