---
card_schema: "1.0"
package: juice_analytics
version: 0.1.0
requires:
  juice: ">=1.4.0"
updated: 2026-06-09
---

# juice_analytics — AI card

> Event/screen tracking as a bloc: fan events out to one or more vendor sinks
> behind a consent gate, drop (counted) when consent is off. Read repo
> `AGENTS.md` for the Juice mental model + gotchas.

## Purpose

**Owns:** consent state + tracking bookkeeping (counts, current screen/user).
**Does NOT own:** the vendor SDK (each `AnalyticsSink` is an adapter) or your
event schema/naming.

## When to use

You need to record events/screens and route them to one or more providers
(Firebase, Mixpanel, Segment, …) without coupling app code to a vendor SDK, and
you need a privacy consent gate. For crash/error reporting use
`juice_observability`; for feature gating use `juice_flags`.

## Install

```yaml
dependencies:
  juice_analytics: ^0.1.0
```

## Construct

No required seam — defaults to a single `NoopAnalyticsSink` (events discarded)
so it's safe before a provider is wired. `withConfig` creates **and** initializes
(seeds the consent flag) in one step:

```dart
final analytics = AnalyticsBloc.withConfig(AnalyticsConfig(
  sinks: [FirebaseAnalyticsSink(), if (kDebugMode) ConsoleAnalyticsSink()],
  initiallyEnabled: true,   // false → drop until setConsent(true)
));
```

## Seams

```dart
// A destination (vendor adapter). The bloc isolates each sink — a throw in one
// must NOT break tracking for the others. Defaults: NoopAnalyticsSink (discards),
// ConsoleAnalyticsSink (prints; dev/tests).
abstract class AnalyticsSink {
  Future<void> logEvent(String name, Map<String, Object?> params);
  Future<void> setScreen(String name);
  Future<void> setUser(String? userId, Map<String, Object?> traits);
  Future<void> flush();    // no-op if the vendor batches internally
  Future<void> dispose();
}
```

## API

```dart
void log(String name, [Map<String, Object?> params = const {}]);
void screen(String name);
void setUser(String? userId, [Map<String, Object?> traits = const {}]);
void setConsent(bool enabled);
void flush();
List<AnalyticsSink> get sinks;
```

## Events

| Event | Effect |
|---|---|
| `InitializeAnalyticsEvent(config)` | apply config, seed `enabled` from `initiallyEnabled` |
| `LogEventEvent(name, params)` | fan out to sinks (or drop + `droppedCount++` if disabled) |
| `SetScreenEvent(name)` | fan out + record `screenName` (dropped, uncounted, if disabled) |
| `SetUserEvent(userId, traits)` | always record `userId`; forward identity to sinks only if enabled |
| `SetConsentEvent(enabled)` | toggle `enabled` (no-op if unchanged) |
| `FlushAnalyticsEvent` | `flush()` every sink |

## State

```dart
class AnalyticsState {           // BlocState
  bool enabled;                  // consent gate
  String? userId; String? screenName;
  int eventCount;                // forwarded to sinks this session
  int droppedCount;              // dropped because consent was off
}
// initial: enabled=true, counts 0
```

No derived getters; no event payloads are retained (the events go to the sinks).

## Rebuild groups

| Group | Emitted when |
|---|---|
| `AnalyticsGroups.status` → `analytics:status` | consent/user/counts changed (also on every log/drop) |
| `AnalyticsGroups.screen` → `analytics:screen` | current screen changed |

`AnalyticsGroups.all = {status, screen}`.

## Recipes

```dart
// 1. Vendor sink adapter (Firebase shown; same shape for Mixpanel/Segment/…)
class FirebaseAnalyticsSink implements AnalyticsSink {
  final fb = FirebaseAnalytics.instance;
  @override Future<void> logEvent(String n, Map<String, Object?> p) =>
      fb.logEvent(name: n, parameters: p.cast());
  @override Future<void> setScreen(String n) => fb.logScreenView(screenName: n);
  @override Future<void> setUser(String? id, Map<String, Object?> t) async {
    await fb.setUserId(id: id);
    for (final e in t.entries) await fb.setUserProperty(name: e.key, value: '${e.value}');
  }
  @override Future<void> flush() async {}
  @override Future<void> dispose() async {}
}

// 2. Consent banner action
onAccept: () => analytics.setConsent(true);

// 3. Bind a widget to the current screen (selective rebuild)
class ScreenLabel extends StatelessJuiceWidget<AnalyticsBloc> {
  ScreenLabel({super.key}) : super(groups: {AnalyticsGroups.screen});
  @override Widget onBuild(BuildContext c, StreamStatus s) =>
      Text(bloc.state.screenName ?? '—');
}
```

## Testing

Headless — fake the sink, drive via the convenience API, `settle()`:

```dart
class RecordingSink implements AnalyticsSink {
  final events = <String>[]; bool throwOnLog = false;
  @override Future<void> logEvent(String n, Map<String, Object?> p) async {
    if (throwOnLog) throw StateError('boom'); events.add(n);
  }
  // setScreen/setUser/flush/dispose → record or no-op
}
final sink = RecordingSink();
final bloc = AnalyticsBloc.withConfig(AnalyticsConfig(sinks: [sink]));
bloc.log('checkout');
await settle();                  // Future.delayed(20ms)
expect(sink.events, ['checkout']);
// Disable → drop + count, not buffer:
bloc.setConsent(false); await settle();
bloc.log('x'); await settle();
expect(bloc.state.droppedCount, 1);
```

## Failure modes

- A sink that throws is **isolated** in `fanOut` — the throw is swallowed so the
  other sinks (and tracking) keep working; nothing is surfaced to the caller.
- The convenience API is fire-and-forget (`send`), so `log`/`screen` never throw
  synchronously even if a sink would.
- `close()` disposes every sink (errors swallowed).

## Anti-patterns

- ❌ Reaching into a vendor SDK directly from app code — go through a sink so the
  consent gate and fan-out apply uniformly.
- ❌ Expecting pre-consent events to flush after `setConsent(true)` — they are
  dropped, never buffered, by design (privacy).
- ❌ Throwing from a sink on the hot path expecting it to abort tracking — it
  won't; failures are isolated and silent.
- ❌ Using `NoopAnalyticsSink` in production thinking it records — it discards.

## Invariants

- **Consent gate:** `enabled == false` drops `logEvent`/`setScreen` (the former
  counted in `droppedCount`); `setUser` still records the id locally but doesn't
  forward identity to sinks.
- **Fan-out isolation:** one sink's failure never affects the others.
- No event payloads are retained in state — only consent + bookkeeping.

## See also

`SPEC.md` (boundary/consent) · `README.md` (narrative) · repo `AGENTS.md` (framework).
