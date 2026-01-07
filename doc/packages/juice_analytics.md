# juice_analytics

> Canonical specification for the juice_analytics companion package

## Purpose

Analytics and event tracking with batching, offline support, and multiple provider support.

---

## Dependencies

**External:** None

**Juice Packages:**
- juice_network - Send events to backend
- juice_storage - Offline event queue

---

## Architecture

### Bloc: `AnalyticsBloc`

**Lifecycle:** Permanent

### State

```dart
class AnalyticsState extends BlocState {
  final bool isEnabled;
  final String? userId;
  final Map<String, dynamic> userProperties;
  final List<AnalyticsEvent> eventQueue;
  final Map<String, ProviderStatus> providers;
  final AnalyticsConfiguration config;
}
```

### Events

- `InitializeAnalyticsEvent` - Configure providers
- `TrackEvent` - Track custom event
- `TrackScreenViewEvent` - Track screen view
- `SetUserIdEvent` - Set user identifier
- `FlushEventsEvent` - Force send queued events
- `DisableAnalyticsEvent` - Disable tracking (GDPR)

### Rebuild Groups

- `analytics:status` - Provider status
- `analytics:queue` - Queue size changes
- `analytics:user` - User identity changes

---

## Integration Points

**EventSubscription from:**
- juice_auth - Auth events
- juice_messaging - Messaging metrics
- juice_location - Location events

---

## Open Questions

_To be discussed_
