# juice_network

> Canonical specification for the juice_network companion package

## Purpose

HTTP client with Dio integration, request tracking, caching, and automatic retry.

---

## Dependencies

**External:**
- dio

**Juice Packages:**
- juice_connectivity (optional - for offline detection)

---

## Architecture

### Bloc: `NetworkBloc`

**Lifecycle:** Permanent

### State

```dart
class NetworkState extends BlocState {
  final bool isInitialized;
  final Map<String, RequestStatus> activeRequests;
  final Map<String, CachedResponse> responseCache;
  final NetworkConfiguration config;
}
```

### Events

- `InitializeNetworkEvent` - Configure Dio instance
- `ExecuteRequestEvent` - Make HTTP request
- `CancelRequestEvent` - Cancel in-flight request
- `ClearCacheEvent` - Clear response cache
- `UpdateConfigEvent` - Update headers, timeout, base URL

### Rebuild Groups

- `network:request:{id}` - Per-request status
- `network:config` - Configuration changes
- `network:cache` - Cache state changes

---

## Integration Points

**StateRelay from:**
- juice_connectivity - Offline detection

**EventSubscription from:**
- juice_auth - Token injection

---

## Open Questions

_To be discussed_
