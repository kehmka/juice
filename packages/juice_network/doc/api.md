---
layout: default
title: API Reference
nav_order: 5
---

# API Reference

Complete reference for juice_network's public API.

## FetchBloc

The main bloc for HTTP operations.

### Constructor

```dart
FetchBloc({
  required StorageBloc storageBloc,
})
```

### State: FetchState

```dart
class FetchState extends BlocState {
  final bool isInitialized;
  final FetchConfig? config;
  final Map<String, RequestStatus> activeRequests;
  final FetchStats stats;
  final CacheStats cacheStats;
  final Object? lastError;
  final Object? lastResponse;
}
```

| Property | Type | Description |
|----------|------|-------------|
| `isInitialized` | `bool` | Whether InitializeFetchEvent has been sent |
| `config` | `FetchConfig?` | Current configuration |
| `activeRequests` | `Map<String, RequestStatus>` | Currently inflight requests |
| `stats` | `FetchStats` | Request statistics |
| `cacheStats` | `CacheStats` | Cache statistics |
| `lastError` | `Object?` | Most recent error |
| `lastResponse` | `Object?` | Most recent decoded response |

### Computed Properties

```dart
int get inflightCount  // Number of inflight requests
```

---

## Events

### InitializeFetchEvent

Initialize FetchBloc with configuration. Must be called before making requests.

```dart
InitializeFetchEvent({
  required FetchConfig config,
})
```

### GetEvent

Make an HTTP GET request.

```dart
GetEvent({
  required String url,
  Map<String, dynamic>? queryParameters,
  Map<String, String>? headers,
  CachePolicy? cachePolicy,
  Duration? ttl,
  T Function(dynamic)? decode,
})
```

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `url` | `String` | required | URL path (appended to baseUrl) |
| `queryParameters` | `Map<String, dynamic>?` | null | Query parameters |
| `headers` | `Map<String, String>?` | null | Additional headers |
| `cachePolicy` | `CachePolicy?` | from config | Caching strategy |
| `ttl` | `Duration?` | from config | Cache time-to-live |
| `decode` | `Function?` | null | Response decoder |

### PostEvent

Make an HTTP POST request.

```dart
PostEvent({
  required String url,
  dynamic body,
  Map<String, dynamic>? queryParameters,
  Map<String, String>? headers,
  T Function(dynamic)? decode,
})
```

### PutEvent

Make an HTTP PUT request.

```dart
PutEvent({
  required String url,
  dynamic body,
  Map<String, dynamic>? queryParameters,
  Map<String, String>? headers,
  T Function(dynamic)? decode,
})
```

### PatchEvent

Make an HTTP PATCH request.

```dart
PatchEvent({
  required String url,
  dynamic body,
  Map<String, dynamic>? queryParameters,
  Map<String, String>? headers,
  T Function(dynamic)? decode,
})
```

### DeleteEvent

Make an HTTP DELETE request.

```dart
DeleteEvent({
  required String url,
  Map<String, dynamic>? queryParameters,
  Map<String, String>? headers,
  T Function(dynamic)? decode,
})
```

### ClearCacheEvent

Clear all cached responses.

```dart
ClearCacheEvent()
```

### ResetStatsEvent

Reset all statistics counters to zero.

```dart
ResetStatsEvent()
```

---

## Configuration

### FetchConfig

```dart
FetchConfig({
  required String baseUrl,
  Duration connectTimeout = const Duration(seconds: 30),
  Duration receiveTimeout = const Duration(seconds: 30),
  Duration sendTimeout = const Duration(seconds: 30),
  Duration defaultTtl = const Duration(minutes: 5),
  CachePolicy defaultCachePolicy = CachePolicy.networkFirst,
  int maxRetries = 3,
  Map<String, String> headers = const {},
})
```

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `baseUrl` | `String` | required | Base URL for all requests |
| `connectTimeout` | `Duration` | 30s | Connection timeout |
| `receiveTimeout` | `Duration` | 30s | Response timeout |
| `sendTimeout` | `Duration` | 30s | Request body send timeout |
| `defaultTtl` | `Duration` | 5min | Default cache TTL |
| `defaultCachePolicy` | `CachePolicy` | networkFirst | Default caching strategy |
| `maxRetries` | `int` | 3 | Max retry attempts on failure |
| `headers` | `Map<String, String>` | {} | Default headers for all requests |

---

## Cache Policy

```dart
enum CachePolicy {
  networkFirst,        // Network first, cache fallback
  cacheFirst,          // Cache first, network if miss
  staleWhileRevalidate, // Return stale, refresh in background
  cacheOnly,           // Cache only, no network
  networkOnly,         // Network only, no cache
}
```

---

## Statistics

### FetchStats

```dart
class FetchStats {
  final int totalRequests;
  final int successCount;
  final int failureCount;
  final int retryCount;
  final int coalescedCount;
  final int cacheHits;
  final int cacheMisses;
  final int bytesReceived;
  final int bytesSent;
  final double avgResponseTimeMs;
}
```

| Property | Description |
|----------|-------------|
| `totalRequests` | Total requests sent |
| `successCount` | Successful responses |
| `failureCount` | Failed requests |
| `retryCount` | Retry attempts made |
| `coalescedCount` | Requests that attached to existing inflight |
| `cacheHits` | Responses served from cache |
| `cacheMisses` | Cache misses requiring network |
| `bytesReceived` | Total bytes received |
| `bytesSent` | Total bytes sent |
| `avgResponseTimeMs` | Average response time in milliseconds |

**Computed Properties:**

```dart
double get successRate  // Success percentage (0-100)
double get hitRate      // Cache hit percentage (0-100)
```

### CacheStats

```dart
class CacheStats {
  final int entryCount;
  final int totalBytes;
}
```

---

## Request Status

### RequestStatus

```dart
class RequestStatus {
  final RequestPhase phase;
  final int attempt;
  final DateTime startedAt;
}
```

### RequestPhase

```dart
enum RequestPhase {
  pending,    // Queued, not yet started
  inflight,   // Currently executing
  completed,  // Successfully completed
  failed,     // Failed after all retries
  cancelled,  // Cancelled by user
}
```

---

## Rebuild Groups

| Group | Triggers When |
|-------|---------------|
| `fetch:inflight` | Inflight count changes |
| `fetch:stats` | Statistics update |
| `fetch:cache` | Cache changes |
| `fetch:request:{METHOD}:{path}` | Specific request status changes |

**Example:**

```dart
// Rebuild on any stats change
class StatsWidget extends StatelessJuiceWidget<FetchBloc> {
  StatsWidget({super.groups = const {'fetch:stats'}});
}

// Rebuild when /posts/1 request status changes
class PostWidget extends StatelessJuiceWidget<FetchBloc> {
  PostWidget({super.groups = const {'fetch:request:GET:/posts/1'}});
}
```
