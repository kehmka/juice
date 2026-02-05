---
layout: default
title: API Reference
nav_order: 7
---

# API Reference

Complete reference for juice_network's public API.

## FetchBloc

The main bloc for HTTP operations.

### Constructor

```dart
FetchBloc({
  required StorageBloc storageBloc,
  Dio? dio,
  AuthIdentityProvider? authIdentityProvider,
})
```

| Parameter | Type | Description |
|-----------|------|-------------|
| `storageBloc` | `StorageBloc` | Required. Storage bloc for cache persistence |
| `dio` | `Dio?` | Optional custom Dio instance |
| `authIdentityProvider` | `AuthIdentityProvider?` | User identity for cache isolation (required if using AuthInterceptor) |

### State: FetchState

```dart
class FetchState extends BlocState {
  final bool isInitialized;
  final FetchConfig config;
  final Map<String, RequestStatus> activeRequests;
  final int inflightCount;
  final NetworkStats stats;
  final CacheStats cacheStats;
  final FetchError? lastError;
}
```

| Property | Type | Description |
|----------|------|-------------|
| `isInitialized` | `bool` | Whether InitializeFetchEvent has been sent |
| `config` | `FetchConfig` | Current configuration |
| `activeRequests` | `Map<String, RequestStatus>` | Currently inflight requests by canonical key |
| `inflightCount` | `int` | Number of inflight requests |
| `stats` | `NetworkStats` | Request statistics |
| `cacheStats` | `CacheStats` | Cache statistics |
| `lastError` | `FetchError?` | Most recent error |

### Computed Properties

```dart
bool get hasInflight    // Whether any requests are inflight
bool get hasError       // Whether an error occurred recently
bool isActive(key)      // Check if request is active
bool isInflight(key)    // Check if request is inflight
```

---

## Events

### InitializeFetchEvent

Initialize FetchBloc with configuration. Must be called before making requests.

```dart
InitializeFetchEvent({
  FetchConfig config = const FetchConfig(),
  List<FetchInterceptor>? interceptors,
})
```

### ReconfigureInterceptorsEvent

Change interceptors on an already-initialized FetchBloc.

```dart
ReconfigureInterceptorsEvent({
  required List<FetchInterceptor> interceptors,
})
```

### GetEvent

Make an HTTP GET request.

```dart
GetEvent({
  required String url,
  Map<String, dynamic>? queryParams,
  Map<String, String>? headers,
  CachePolicy? cachePolicy,
  Duration? ttl,
  bool cacheAuthResponses = false,
  bool forceCache = false,
  bool allowStaleOnError = true,
  bool retryable = true,
  int? maxAttempts,
  dynamic Function(dynamic)? decode,
  String? scope,
  String? variant,
  RequestKey? keyOverride,
})
```

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `url` | `String` | required | URL path (appended to baseUrl) |
| `queryParams` | `Map<String, dynamic>?` | null | Query parameters |
| `headers` | `Map<String, String>?` | null | Additional headers |
| `cachePolicy` | `CachePolicy?` | from config | Caching strategy |
| `ttl` | `Duration?` | from config | Cache time-to-live |
| `cacheAuthResponses` | `bool` | false | Cache authenticated responses |
| `forceCache` | `bool` | false | Cache even if no-store header |
| `allowStaleOnError` | `bool` | true | Use stale cache on network error |
| `retryable` | `bool` | true | Enable retry on failure |
| `maxAttempts` | `int?` | from config | Max retry attempts |
| `decode` | `Function?` | null | Response decoder |
| `scope` | `String?` | null | Scope for cancellation grouping |
| `variant` | `String?` | null | Cache key variant namespace |
| `keyOverride` | `RequestKey?` | null | Override computed request key |

### PostEvent

Make an HTTP POST request.

```dart
PostEvent({
  required String url,
  Object? body,
  Map<String, dynamic>? queryParams,
  Map<String, String>? headers,
  CachePolicy? cachePolicy,
  Duration? ttl,
  bool cacheAuthResponses = false,
  bool forceCache = false,
  bool allowStaleOnError = false,
  bool retryable = false,
  int? maxAttempts,
  String? idempotencyKey,
  dynamic Function(dynamic)? decode,
  String? scope,
  String? variant,
  RequestKey? keyOverride,
})
```

**Note:** POST defaults to `retryable: false`. Set `retryable: true` with an `idempotencyKey` for safe retries.

### PutEvent

Make an HTTP PUT request.

```dart
PutEvent({
  required String url,
  Object? body,
  // ... same parameters as PostEvent
  bool retryable = true,  // PUT is idempotent
})
```

### PatchEvent

Make an HTTP PATCH request.

```dart
PatchEvent({
  required String url,
  Object? body,
  // ... same parameters as PostEvent
  bool retryable = false,  // Requires idempotencyKey
})
```

### DeleteEvent

Make an HTTP DELETE request.

```dart
DeleteEvent({
  required String url,
  Map<String, dynamic>? queryParams,
  Map<String, String>? headers,
  CachePolicy? cachePolicy,
  bool retryable = true,  // DELETE is idempotent
  int? maxAttempts,
  dynamic Function(dynamic)? decode,
  String? scope,
  String? variant,
  RequestKey? keyOverride,
})
```

### HeadEvent

Make an HTTP HEAD request.

```dart
HeadEvent({
  required String url,
  Map<String, dynamic>? queryParams,
  Map<String, String>? headers,
  bool retryable = true,
  String? scope,
})
```

### Cache Events

```dart
InvalidateCacheEvent({
  RequestKey? key,
  String? urlPattern,
  String? namespace,
  bool includeExpired = true,
})

ClearCacheEvent({String? namespace})

PruneCacheEvent({
  int? targetBytes,
  bool removeExpiredFirst = true,
})

CleanupExpiredCacheEvent({String? namespace})
```

| Parameter | Type | Description |
|-----------|------|-------------|
| `key` | `RequestKey?` | Invalidate a specific cache entry |
| `urlPattern` | `String?` | Regex pattern to match against cache keys |
| `namespace` | `String?` | Namespace prefix to filter entries (e.g., user ID for auth isolation) |
| `includeExpired` | `bool` | If false, only invalidates non-expired entries (default: true) |

### Cancellation Events

```dart
CancelRequestEvent({
  required RequestKey key,
  String? reason,
})

CancelScopeEvent({
  required String scope,
  String? reason,
})

CancelAllEvent({String? reason})
```

### Observability Events

```dart
ResetStatsEvent()
ClearLastErrorEvent()
```

---

## Configuration

### FetchConfig

```dart
FetchConfig({
  String? baseUrl,
  Duration connectTimeout = const Duration(seconds: 30),
  Duration receiveTimeout = const Duration(seconds: 30),
  Duration sendTimeout = const Duration(seconds: 30),
  CachePolicy defaultCachePolicy = CachePolicy.networkFirst,
  Duration? defaultTtl,
  int maxCacheSize = 50 * 1024 * 1024,  // 50 MB
  int maxConcurrentRequests = 10,
  Map<String, String> defaultHeaders = const {},
  bool followRedirects = true,
  int maxRedirects = 5,
  int defaultMaxRetries = 3,
  bool validateStatus = true,
})
```

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `baseUrl` | `String?` | null | Base URL for all requests |
| `connectTimeout` | `Duration` | 30s | Connection timeout |
| `receiveTimeout` | `Duration` | 30s | Response timeout |
| `sendTimeout` | `Duration` | 30s | Request body send timeout |
| `defaultCachePolicy` | `CachePolicy` | networkFirst | Default caching strategy |
| `defaultTtl` | `Duration?` | null | Default cache TTL |
| `maxCacheSize` | `int` | 50 MB | Maximum cache size in bytes |
| `maxConcurrentRequests` | `int` | 10 | Max concurrent requests (excess queued) |
| `defaultHeaders` | `Map<String, String>` | {} | Default headers for all requests |
| `followRedirects` | `bool` | true | Follow HTTP redirects |
| `maxRedirects` | `int` | 5 | Maximum redirects to follow |
| `defaultMaxRetries` | `int` | 3 | Default retry attempts on failure |
| `validateStatus` | `bool` | true | Throw on 4xx/5xx status codes |

### AuthIdentityProvider

```dart
typedef AuthIdentityProvider = String? Function();
```

Provides a user-specific identity for cache isolation. **Required** when using `AuthInterceptor` to prevent cross-user cache leaks.

```dart
FetchBloc(
  storageBloc: storageBloc,
  authIdentityProvider: () => authBloc.state.userId,
)
```

---

## Cache Policy

```dart
enum CachePolicy {
  networkFirst,         // Network first, cache fallback
  cacheFirst,           // Cache first, network if miss
  staleWhileRevalidate, // Return stale, refresh in background
  cacheOnly,            // Cache only, no network
  networkOnly,          // Network only, no cache
}
```

---

## Statistics

### NetworkStats

```dart
class NetworkStats {
  final int totalRequests;
  final int successCount;
  final int failureCount;
  final int retryCount;
  final int coalescedCount;
  final int cacheHits;
  final int cacheMisses;
  final int bytesReceived;
  final int bytesSent;

  double get avgResponseTimeMs;  // Average of successful requests only
  double get successRate;        // Success percentage (0-100)
  double get hitRate;            // Cache hit percentage (0-100)
}
```

| Property | Description |
|----------|-------------|
| `totalRequests` | Total requests sent (success + failure) |
| `successCount` | Successful responses |
| `failureCount` | Failed requests |
| `retryCount` | Retry attempts made |
| `coalescedCount` | Requests that joined existing inflight |
| `cacheHits` | Responses served from cache |
| `cacheMisses` | Cache misses requiring network |
| `bytesReceived` | Total bytes received |
| `bytesSent` | Total bytes sent |
| `avgResponseTimeMs` | Average response time (successful only) |

### CacheStats

```dart
class CacheStats {
  final int entryCount;
  final int totalBytes;
  final int expiredCount;
}
```

---

## Request Status

### RequestStatus

```dart
class RequestStatus {
  final RequestKey key;
  final RequestPhase phase;
  final String? scope;
  final CancelToken? cancelToken;
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

## Errors

All errors extend `FetchError`:

```dart
sealed class FetchError {
  final RequestKey? requestKey;
  final int? statusCode;
  final Duration? elapsed;
  final String message;
  final Object? cause;
  final StackTrace? stackTrace;
}
```

| Error Type | Description |
|------------|-------------|
| `NetworkError` | Network connectivity error |
| `TimeoutError` | Request timed out (connect/send/receive) |
| `HttpError` | HTTP error response |
| `ClientError` | 4xx client error |
| `ServerError` | 5xx server error |
| `DecodeError` | JSON parse or decoder function failed |
| `CancelledError` | Request was cancelled |

---

## Rebuild Groups

| Group | Triggers When |
|-------|---------------|
| `fetch:config` | Configuration changes |
| `fetch:inflight` | Inflight count changes |
| `fetch:stats` | Statistics update |
| `fetch:cache` | Cache changes |
| `fetch:error` | Error state changes |
| `fetch:request:{canonical}` | Specific request status changes |
| `fetch:url:{pattern}` | Requests matching URL pattern |

**Example:**

```dart
// Rebuild on any stats change
class StatsWidget extends StatelessJuiceWidget<FetchBloc> {
  StatsWidget({super.groups = const {'fetch:stats'}});
}

// Rebuild when GET /posts/1 request status changes
class PostWidget extends StatelessJuiceWidget<FetchBloc> {
  PostWidget({super.groups = const {'fetch:request:GET:/posts/1'}});
}
```

---

## Interceptors

### FetchInterceptor

Base class for interceptors. Interceptors run AFTER cache lookup and coalescer check.

```dart
abstract class FetchInterceptor {
  Future<RequestOptions> onRequest(RequestOptions options);
  Future<Response<dynamic>> onResponse(Response<dynamic> response);
  Future<dynamic> onError(DioException error);
  int get priority;  // Lower runs first for onRequest
}
```

### InterceptorPriority

```dart
abstract class InterceptorPriority {
  static const logging = 0;
  static const auth = 10;
  static const refreshToken = 15;
  static const retry = 20;
  static const etag = 30;
  static const metrics = 100;
}
```

### Built-in Interceptors

- `AuthInterceptor` - Add authentication headers
- `RetryInterceptor` - Retry with exponential backoff
- `LoggingInterceptor` - Log requests/responses
- `ETagInterceptor` - Conditional requests with ETag
- `RefreshTokenInterceptor` - Handle 401 with token refresh
