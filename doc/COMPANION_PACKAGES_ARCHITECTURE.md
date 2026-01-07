# Juice Companion Packages Architecture

## Overview

This document provides a high-level overview of the 11 companion packages that extend the Juice framework. Each package has its own canonical specification file in the `doc/packages/` directory.

---

## Package Dependency Graph

```
                        juice (core)
                             |
           +-----------------+-----------------+
           |                 |                 |
      juice_storage    juice_network     juice_config
           |                 |                 |
           +--------+--------+--------+--------+
                    |                 |
              juice_auth        juice_connectivity
                    |                 |
           +--------+--------+--------+--------+
           |                 |                 |
     juice_form      juice_messaging    juice_location
           |                                   |
     juice_theme                        juice_analytics
           |
    juice_animation
```

---

## Package Specifications

| Package | Purpose | Spec |
|---------|---------|------|
| **juice_storage** | Local storage, caching, secure storage | [View Spec](packages/juice_storage.md) |
| **juice_network** | HTTP client with Dio, retry, caching | [View Spec](packages/juice_network.md) |
| **juice_config** | Environment config, feature flags | [View Spec](packages/juice_config.md) |
| **juice_connectivity** | Network/Bluetooth monitoring | [View Spec](packages/juice_connectivity.md) |
| **juice_auth** | Authentication workflows, tokens | [View Spec](packages/juice_auth.md) |
| **juice_form** | Form handling, validation | [View Spec](packages/juice_form.md) |
| **juice_theme** | Theme management, persistence | [View Spec](packages/juice_theme.md) |
| **juice_animation** | Bloc-controlled animations | [View Spec](packages/juice_animation.md) |
| **juice_messaging** | WebSocket real-time messaging | [View Spec](packages/juice_messaging.md) |
| **juice_location** | Location, geofencing, geocoding | [View Spec](packages/juice_location.md) |
| **juice_analytics** | Event tracking, batching, offline | [View Spec](packages/juice_analytics.md) |

---

## Direct Dependencies

| Package | Depends On |
|---------|-----------|
| juice_storage | juice, hive, shared_prefs, sqflite, flutter_secure_storage |
| juice_network | juice, dio |
| juice_config | juice, juice_storage |
| juice_connectivity | juice, connectivity_plus, flutter_blue_plus |
| juice_auth | juice, juice_network, juice_storage |
| juice_messaging | juice, juice_network, juice_connectivity |
| juice_location | juice, geolocator, juice_connectivity |
| juice_form | juice |
| juice_theme | juice, juice_storage |
| juice_animation | juice |
| juice_analytics | juice, juice_network, juice_storage |

---

## Recommended Implementation Order

### Phase 1: Foundation
1. **juice_storage** - No Juice dependencies, foundational for persistence
2. **juice_network** - No Juice dependencies, foundational for API calls
3. **juice_config** - Depends on juice_storage, needed by many packages

### Phase 2: Infrastructure
4. **juice_connectivity** - Network/Bluetooth status awareness
5. **juice_auth** - Auth flows, depends on network + storage

### Phase 3: Features
6. **juice_messaging** - Real-time communication
7. **juice_location** - Location services
8. **juice_analytics** - Event tracking

### Phase 4: UI Layer
9. **juice_form** - Form handling
10. **juice_theme** - Theme management
11. **juice_animation** - Animation patterns

---

## Shared Patterns

### 1. Initialization Pattern
All packages use `StatefulUseCaseBuilder` with `initialEventBuilder` for auto-init.

### 2. API Pattern
Event-driven with helper methods for cleaner usage:
```dart
// Helper wraps event
Future<T?> read<T>(String key) async {
  final status = await sendAndWait(ReadEvent<T>(key: key));
  return status.state.lastValue as T?;
}
```

### 3. Cross-Bloc Communication
- `StateRelay` for state-to-event transformation
- `EventSubscription` for event forwarding
- `StatusRelay` for full status handling

### 4. Lifecycle Management
- **Permanent:** AuthBloc, ConfigBloc, ThemeBloc, AnalyticsBloc, ConnectivityBloc, StorageBloc, NetworkBloc
- **Feature:** FormBloc instances per flow
- **Leased:** AnimationBloc per widget

### 5. Error Handling
All packages extend `JuiceException` with `isRetryable` property.

### 6. Rebuild Group Convention
`{package}:{category}:{id?}` - e.g., `storage:hive:settings`, `network:request:abc123`

### 7. Network Operations
Use `RetryableUseCaseBuilder` for all network calls.

---

## Specification Status

| Package | Status |
|---------|--------|
| juice_storage | ✅ Detailed |
| juice_network | 📝 Outline |
| juice_config | 📝 Outline |
| juice_connectivity | 📝 Outline |
| juice_auth | 📝 Outline |
| juice_form | 📝 Outline |
| juice_theme | 📝 Outline |
| juice_animation | 📝 Outline |
| juice_messaging | 📝 Outline |
| juice_location | 📝 Outline |
| juice_analytics | 📝 Outline |

---

## Reference Files

- `lib/src/bloc/src/juice_bloc.dart` - Core bloc pattern
- `lib/src/bloc/src/use_case_builders/src/state_relay.dart` - Cross-bloc communication
- `lib/src/bloc/src/use_case_builders/src/retryable_use_case_builder.dart` - Retry pattern
- `example/lib/blocs/chat/chat_bloc.dart` - WebSocket pattern for juice_messaging
