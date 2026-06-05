# juice_analytics Specification

> **Status:** Implemented (shipping).
> **Package:** `juice_analytics`
> **Primary Bloc:** `AnalyticsBloc`

## Overview

Event/screen tracking fanned out to one or more `AnalyticsSink`s behind a consent
gate. Vendor-free — sinks are adapters.

## Domain boundary

- **Owns:** consent state + tracking bookkeeping (counts, current screen/user).
- **Does NOT own:** the vendor SDK (a sink), or event schema.

## Seam

`AnalyticsSink`: `logEvent` / `setScreen` / `setUser` / `flush` / `dispose`.
Config takes a **list** of sinks (fan-out). Defaults to `NoopAnalyticsSink`;
`ConsoleAnalyticsSink` for dev. The bloc isolates each sink — a throw in one
doesn't affect the others.

## Consent (privacy)

`state.enabled` gates tracking. When off, `logEvent`/`setScreen` are **dropped**
(events counted in `droppedCount`), never buffered — granting consent later can't
flush pre-consent data. `setUser` records the id in state but forwards identity
to sinks only with consent.

## State

`enabled`, `userId`, `screenName`, `eventCount`, `droppedCount`. Groups:
`analytics:status`, `analytics:screen`.

## Events & use cases (6)

`InitializeAnalyticsEvent`, `LogEventEvent`, `SetScreenEvent`, `SetUserEvent`,
`SetConsentEvent`, `FlushAnalyticsEvent`. API: `log`, `screen`, `setUser`,
`setConsent`, `flush`.

## Testing

Recording fake sink: fan-out to multiple sinks, throwing-sink isolation, consent
drop + count, consent grant resumes flow, flush + dispose reach sinks. 6 tests.

## Spec Version

| Version | Date | Status |
|---|---|---|
| 1.0 | 2026-05-28 | Implemented |
