---
card_schema: "1.0"
package: juice_observability
version: 0.2.0
requires:
  juice: ">=1.5.0"
updated: 2026-06-09
---

# juice_observability — AI card

> Crash reporting + breadcrumbs as a bloc: install global error handlers, keep a
> bounded breadcrumb ring, and fan reports out to one or more vendor reporters.
> Read repo `AGENTS.md` for the Juice mental model + gotchas.

## Purpose

**Owns:** the capture pipeline — global handlers, the breadcrumb ring, and
fan-out to reporters.
**Does NOT own:** the vendor SDK (each `CrashReporter` is an adapter) or basic
logging (`juice`'s `DefaultJuiceLogger`; this is app-level crash reporting).

## When to use

You need uncaught-error capture + crash reports routed to Sentry/Crashlytics/…
without coupling app code to a vendor SDK, plus a breadcrumb trail attached to
each report. For event/screen tracking use `juice_analytics`.

## Install

```yaml
dependencies:
  juice_observability: ^0.1.0
```

## Construct

No required seam — defaults to `NoopCrashReporter` (safe before a provider is
wired). `withConfig` initializes and, when `captureUncaught`, installs the
global handlers:

```dart
final obs = ObservabilityBloc.withConfig(ObservabilityConfig(
  reporters: [SentryCrashReporter(), if (kDebugMode) ConsoleCrashReporter()],
  captureUncaught: true,   // install FlutterError.onError + PlatformDispatcher.onError
  maxBreadcrumbs: 50,      // 0 disables breadcrumbs
));
obs.breadcrumb('opened checkout');
obs.recordError(e, st);
```

## Seams

```dart
// A destination (vendor adapter). The bloc isolates each — a throw in one must
// NOT break the others. Defaults: NoopCrashReporter; ConsoleCrashReporter (dev).
abstract class CrashReporter {
  Future<void> recordError(Object error, StackTrace? stack,
      {bool fatal, List<Breadcrumb> breadcrumbs});  // breadcrumbs = ring snapshot
  Future<void> addBreadcrumb(Breadcrumb crumb);
  Future<void> setUser(String? userId);
  Future<void> setContext(String key, Object? value);
  Future<void> dispose();
}

class Breadcrumb {           // message + optional category + data map
  final String message; final String? category; final Map<String, Object?> data;
  const Breadcrumb(this.message, {this.category, this.data = const {}});
}
```

## API

```dart
void recordError(Object error, [StackTrace? stack, bool fatal = false]);
void breadcrumb(String message, {String? category, Map<String, Object?> data = const {}});
void setUser(String? userId);
void setContext(String key, Object? value);
void setEnabled(bool enabled);
List<Breadcrumb> get breadcrumbs;   // fresh ring snapshot, most recent last
```

## Events

| Event | Effect |
|---|---|
| `InitializeObservabilityEvent(config)` | apply config; install global handlers if `captureUncaught` |
| `RecordErrorEvent(error, stack, {fatal})` | report to reporters with ring; `errorCount++`, `lastError` (skipped if disabled) |
| `AddBreadcrumbEvent(crumb)` | append to ring (trim to `maxBreadcrumbs`) + forward (skipped if disabled / `max<=0`) |
| `SetUserEvent(userId)` | `setUser` across reporters; record `userId` |
| `SetContextEvent(key, value)` | `setContext` across reporters (no state change) |
| `SetEnabledEvent(enabled)` | toggle `enabled` (no-op if unchanged) |

`FlutterError.onError` and `PlatformDispatcher.onError` are auto-wired to send
`RecordErrorEvent` (platform errors `fatal: true`) and chain prior handlers.

## State

```dart
class ObservabilityState {    // BlocState
  bool enabled;               // capture + reporting gate
  int errorCount;             // errors recorded this session
  List<Breadcrumb> breadcrumbs;  // bounded ring snapshot (most recent last)
  String? userId; String? lastError;
}
// initial: enabled=true, errorCount=0, breadcrumbs=[]
```

## Rebuild groups

| Group | Emitted when |
|---|---|
| `ObservabilityGroups.status` → `observability:status` | counts / enabled / lastError / breadcrumb ring / user changed |

`ObservabilityGroups.all = {status}`.

## Concurrency

`RecordErrorEvent` and `AddBreadcrumbEvent` are registered
**`EventConcurrency.sequential`** (juice ≥ 1.5.0): same-type events queue and run
one-at-a-time, so the breadcrumb-ring and error-counter read-modify-writes live
naturally in state (`state.breadcrumbs` / `state.errorCount`) without any
bloc-side accumulator. This is the framework mode that replaced the original
hand-rolled workaround.

## Recipes

```dart
// 1. Vendor reporter adapter (Sentry shown; same shape for Crashlytics/…)
class SentryCrashReporter implements CrashReporter {
  @override Future<void> recordError(Object e, StackTrace? st,
      {bool fatal = false, List<Breadcrumb> breadcrumbs = const []}) async {
    for (final b in breadcrumbs) Sentry.addBreadcrumb(SentryBreadcrumb(message: b.message));
    await Sentry.captureException(e, stackTrace: st);
  }
  @override Future<void> addBreadcrumb(Breadcrumb c) async =>
      Sentry.addBreadcrumb(SentryBreadcrumb(message: c.message, category: c.category));
  @override Future<void> setUser(String? id) => Sentry.configureScope((s) => s.setUser(id == null ? null : SentryUser(id: id)));
  @override Future<void> setContext(String k, Object? v) => Sentry.configureScope((s) => s.setContexts(k, v));
  @override Future<void> dispose() async {}
}

// 2. Leave a trail then report
obs.breadcrumb('tapped pay', category: 'ui');
try { await pay(); } catch (e, st) { obs.recordError(e, st); }

// 3. Privacy toggle
obs.setEnabled(userConsentedToCrashReports);
```

## Testing

Headless — fake the reporter, set `captureUncaught: false` so tests don't hijack
the global handlers:

```dart
class RecordingReporter implements CrashReporter {
  final errors = <Object>[]; final crumbs = <Breadcrumb>[]; bool throwOnError = false;
  @override Future<void> recordError(Object e, StackTrace? st,
      {bool fatal = false, List<Breadcrumb> breadcrumbs = const []}) async {
    if (throwOnError) throw StateError('boom'); errors.add(e);
  }
  @override Future<void> addBreadcrumb(Breadcrumb c) async => crumbs.add(c);
  // setUser/setContext/dispose → record or no-op
}
final r = RecordingReporter();
final bloc = ObservabilityBloc.withConfig(
    ObservabilityConfig(reporters: [r], captureUncaught: false, maxBreadcrumbs: 2));
bloc.breadcrumb('a'); bloc.breadcrumb('b'); bloc.breadcrumb('c');
await settle();                       // Future.delayed(20ms)
expect(bloc.state.breadcrumbs.length, 2);   // ring trimmed to max
bloc.recordError(Exception('x')); await settle();
expect(r.errors, hasLength(1));
```

## Failure modes

- A reporter that throws is **isolated** in `fanOut` — swallowed; the others
  still receive the report and the breadcrumb ring still updates.
- When `enabled == false`, `recordError` and `breadcrumb` are dropped (not
  buffered). `maxBreadcrumbs <= 0` disables breadcrumbs entirely.
- `close()` **restores** the previously-installed global handlers and disposes
  every reporter (errors swallowed). Installing handlers twice is a no-op.

## Anti-patterns

- ❌ Leaving `captureUncaught: true` in unit tests — it hijacks the global error
  handlers for the test process; pass `false`.
- ❌ Mutating `state.breadcrumbs` to add a crumb — go through `breadcrumb()`; the
  ring is bloc-owned for race-safety.
- ❌ Using this for routine logging — that's `DefaultJuiceLogger`; this is crash
  reporting.
- ❌ Expecting events recorded while disabled to flush after `setEnabled(true)` —
  they're dropped.

## Invariants

- **Handler chaining + restore:** prior `FlutterError.onError` /
  `PlatformDispatcher.onError` are called after capture and restored on `close`.
- **Bounded ring:** at most `maxBreadcrumbs`, oldest dropped, attached to the
  next report.
- **Fan-out isolation:** one reporter's failure never affects the others.

## See also

`SPEC.md` (capture/races) · `README.md` (narrative) · repo `AGENTS.md` (framework).
