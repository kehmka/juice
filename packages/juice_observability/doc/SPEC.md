# juice_observability Specification

> **Status:** Implemented (shipping).
> **Package:** `juice_observability`
> **Primary Bloc:** `ObservabilityBloc`

## Overview

Crash reporting + breadcrumbs with automatic global-error capture, fanned out to
one or more `CrashReporter`s. Vendor-free — reporters are adapters.

## Domain boundary

- **Owns:** the capture pipeline (global handlers, breadcrumb ring, fan-out).
- **Does NOT own:** the vendor SDK (a reporter), or basic logging (`juice`'s
  `DefaultJuiceLogger` handles that — this is app-level crash reporting).

## Seam

`CrashReporter`: `recordError(error, stack, {fatal, breadcrumbs})` /
`addBreadcrumb` / `setUser` / `setContext` / `dispose`. Config takes a **list**
(fan-out). Defaults to `NoopCrashReporter`; `ConsoleCrashReporter` for dev. Each
reporter is isolated — a throw in one doesn't affect the others.

## Global capture

On init (when `captureUncaught`), installs `FlutterError.onError` +
`PlatformDispatcher.instance.onError`, **chaining** any handlers already set and
**restoring** them on `close`. Uncaught errors → `RecordErrorEvent` (platform
errors marked fatal).

## State & races

`enabled`, `errorCount`, `breadcrumbs` (bounded ring), `userId`, `lastError`.
Group: `observability:status`.

Juice runs same-type use cases concurrently by default, so the breadcrumb ring
and error counter are held **on the bloc** (mutated synchronously, snapshotted
into state) — a state read-modify-write across rapid fire-and-forget events would
otherwise race. (Alternatively, juice ≥ 1.5.0's `EventConcurrency.sequential` on
those events achieves the same safety; adopting it here is a possible follow-up.)

## Events & use cases (6)

`InitializeObservabilityEvent`, `RecordErrorEvent`, `AddBreadcrumbEvent`,
`SetUserEvent`, `SetContextEvent`, `SetEnabledEvent`. API: `recordError`,
`breadcrumb`, `setUser`, `setContext`, `setEnabled`.

## Testing

Recording fake reporter (`captureUncaught: false`): fan-out with breadcrumbs,
throwing-reporter isolation, disabled drops, **breadcrumb ring trim**, setUser,
close disposes. 7 tests.

## Spec Version

| Version | Date | Status |
|---|---|---|
| 1.0 | 2026-05-28 | Implemented |
