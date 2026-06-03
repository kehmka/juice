# juice_lifecycle Specification

> **Status:** Implemented (shipping).
> **Package:** `juice_lifecycle`
> **Primary Bloc:** `LifecycleBloc`

## Overview

`juice_lifecycle` is an **ambient-signal** foundation bloc owning the app's
lifecycle phase (foreground/background/resume). Consumers react to it —
`juice_permissions` re-checks on resume, `juice_realtime` reconnects, a UI blurs
itself in the task switcher.

## Domain boundary

- **Owns:** the `AppLifecycle` phase + the previous phase.
- **Does NOT own:** what to do on a transition. Consumers decide.

## Dependencies

| Package | Why |
|---------|-----|
| `juice` | core bloc infrastructure |

No third-party dependency — the lifecycle source is Flutter itself
(`AppLifecycleListener`).

## Vendor seam

`LifecycleProvider` is the swap point. The bloc depends on the interface, not on
`WidgetsBinding`, which is what makes it testable without a real binding.

```dart
abstract class LifecycleProvider {
  Stream<AppLifecycle> get changes;
  AppLifecycle get current;
  Future<void> dispose();
}

enum AppLifecycle { resumed, inactive, paused, detached, hidden }
```

The default `WidgetsLifecycleProvider` wraps Flutter's `AppLifecycleListener`,
mapping `AppLifecycleState` → `AppLifecycle`.

## State

```dart
class LifecycleState extends BlocState {
  final AppLifecycle lifecycle;   // default: resumed
  final AppLifecycle? previous;
  final DateTime? lastChangedAt;
  bool get isForeground;          // resumed
  bool get isBackground;          // paused | hidden
  bool get resumedFromBackground; // resumed, coming from paused/hidden/inactive
}
```

## Events

| Event | Effect | Groups |
|-------|--------|--------|
| `InitializeLifecycleEvent(config)` | configure provider, start listening, emit current phase | `lifecycle:state` |
| `LifecycleChangedEvent(phase)` | internal — emit only when the phase changes, tracking `previous` | `lifecycle:state` |

## Testing

`LifecycleBloc` is tested with a fake `LifecycleProvider` driven by a
`StreamController` — transitions, `previous` tracking, the same-phase no-op, and
`resumedFromBackground` all run headlessly. The only binding-touching code,
`WidgetsLifecycleProvider`, is a thin mapping verified by inspection and a
one-time in-app run.

## Spec Version

| Version | Date | Status |
|---------|------|--------|
| 1.0 | 2026-05-28 | Implemented |
