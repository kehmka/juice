# juice_analytics

Event and screen tracking as a [Juice](https://pub.dev/packages/juice) bloc —
fanned out to one or more sinks, behind a consent gate.

[![pub package](https://img.shields.io/pub/v/juice_analytics.svg)](https://pub.dev/packages/juice_analytics)
[![License: MIT](https://img.shields.io/badge/license-MIT-purple.svg)](LICENSE)

## What it owns

Consent state and tracking bookkeeping. It does **not** own a vendor SDK — each
destination is an `AnalyticsSink` adapter (Firebase, Mixpanel, Segment, PostHog).

## Install

```yaml
dependencies:
  juice_analytics: ^0.1.0
```

## Use

```dart
final analytics = AnalyticsBloc.withConfig(AnalyticsConfig(
  sinks: [
    MyFirebaseSink(),
    if (kDebugMode) ConsoleAnalyticsSink(),
  ],
  initiallyEnabled: false,   // require consent first
));

analytics.setConsent(true);
analytics.log('checkout_started', {'cart': 3});
analytics.screen('Cart');
analytics.setUser('u_123', {'plan': 'pro'});
```

## Fan-out + isolation

Every call fans out to all sinks; a sink that throws is isolated so it can't
break tracking for the others.

## Consent-first (privacy)

When consent is off, events are **dropped and counted** — never buffered. So
granting consent later never flushes a backlog of pre-consent events.

```dart
analytics.setConsent(false); // events now drop (state.droppedCount climbs)
```

`setUser` still records the id in state for your UI, but only forwards identity
to sinks with consent.

## Writing a sink

```dart
class MyFirebaseSink implements AnalyticsSink {
  @override
  Future<void> logEvent(String name, Map<String, Object?> params) =>
      FirebaseAnalytics.instance.logEvent(name: name, parameters: params.cast());
  @override
  Future<void> setScreen(String name) =>
      FirebaseAnalytics.instance.logScreenView(screenName: name);
  // setUser / flush / dispose…
}
```

## State

| Field | Meaning |
|---|---|
| `enabled` | consent granted |
| `userId` / `screenName` | current identity / screen |
| `eventCount` | events forwarded this session |
| `droppedCount` | events dropped for lack of consent |

Rebuild groups: `analytics:status`, `analytics:screen`.

## License

MIT License — see [LICENSE](LICENSE).
