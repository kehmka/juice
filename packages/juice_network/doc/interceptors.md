---
layout: default
title: Interceptors
nav_order: 4
---

# Interceptors

Interceptors provide a powerful way to modify requests and responses, add authentication, logging, retry logic, and more.

## How Interceptors Work

Interceptors run in a pipeline around network calls:

1. **onRequest** chain runs (sorted by priority, lowest first)
2. Network call executes
3. **onResponse** chain runs (reverse order) OR **onError** chain runs

Key points:
- Interceptors run AFTER cache lookup and coalescer check
- They only execute for actual network calls, not cache hits
- Each interceptor can modify, pass through, or abort the request/response

## Built-in Interceptors

### AuthInterceptor

Adds authentication headers to requests.

```dart
AuthInterceptor(
  tokenProvider: () async => await secureStorage.read('access_token'),
  headerName: 'Authorization',  // default
  prefix: 'Bearer ',            // default
)
```

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `tokenProvider` | `Future<String?> Function()` | required | Async function returning the token |
| `headerName` | `String` | `'Authorization'` | Header name to set |
| `prefix` | `String` | `'Bearer '` | Prefix before the token |

**Example with different auth schemes:**

```dart
// Bearer token (default)
AuthInterceptor(
  tokenProvider: () async => accessToken,
)
// Adds: Authorization: Bearer <token>

// API Key
AuthInterceptor(
  tokenProvider: () async => apiKey,
  headerName: 'X-API-Key',
  prefix: '',
)
// Adds: X-API-Key: <key>

// Basic auth
AuthInterceptor(
  tokenProvider: () async => base64Encode(utf8.encode('$user:$pass')),
  prefix: 'Basic ',
)
// Adds: Authorization: Basic <encoded>
```

---

### LoggingInterceptor

Logs requests and responses for debugging.

```dart
LoggingInterceptor(
  logger: (msg) => debugPrint(msg),
  logBody: true,
  logHeaders: false,
  logErrors: true,
  maxBodyLength: 1000,
  redactSensitiveHeaders: true,
)
```

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `logger` | `void Function(String)` | required | Output function for logs |
| `logBody` | `bool` | `false` | Log request/response bodies |
| `logHeaders` | `bool` | `false` | Log headers |
| `logErrors` | `bool` | `true` | Log error details |
| `maxBodyLength` | `int` | `1000` | Truncate bodies longer than this |
| `redactSensitiveHeaders` | `bool` | `true` | Replace sensitive header values with [REDACTED] |

**Sensitive headers redacted by default:**
- `authorization`
- `cookie`
- `set-cookie`
- `x-api-key`

**Example output:**

```
→ GET https://api.example.com/users/123
← 200 https://api.example.com/users/123 (142ms)
  Body: {"id": 123, "name": "John"}
```

---

### TimingInterceptor

Adds timing information to requests. Use with LoggingInterceptor to show request duration.

```dart
TimingInterceptor()
```

This interceptor has no parameters. It stores the start time in `request.extra['_startTime']` which LoggingInterceptor reads to calculate elapsed time.

**Always add TimingInterceptor before LoggingInterceptor:**

```dart
interceptors: [
  TimingInterceptor(),   // Records start time
  LoggingInterceptor(    // Reads start time for duration
    logger: print,
  ),
]
```

---

### RetryInterceptor

Automatically retries failed requests with exponential backoff.

```dart
RetryInterceptor(
  maxRetries: 3,
  retryDelays: [
    Duration(milliseconds: 500),
    Duration(seconds: 1),
    Duration(seconds: 2),
  ],
  retryableStatuses: {408, 429, 500, 502, 503, 504},
  shouldRetry: (error) => true,
)
```

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `maxRetries` | `int` | `3` | Maximum retry attempts |
| `retryDelays` | `List<Duration>` | exponential | Delay before each retry |
| `retryableStatuses` | `Set<int>` | timeout/server errors | HTTP status codes to retry |
| `shouldRetry` | `bool Function(DioException)?` | null | Custom retry logic |

**Default retryable status codes:**
- `408` - Request Timeout
- `429` - Too Many Requests
- `500` - Internal Server Error
- `502` - Bad Gateway
- `503` - Service Unavailable
- `504` - Gateway Timeout

---

### ETagInterceptor

Implements HTTP ETag caching for bandwidth optimization.

```dart
ETagInterceptor(
  storage: etagStorage,  // Stores ETag values
)
```

| Parameter | Type | Description |
|-----------|------|-------------|
| `storage` | `ETagStorage` | Storage for ETag values |

**How it works:**
1. On request: Adds `If-None-Match` header with stored ETag
2. On 304 response: Returns cached response (not modified)
3. On 200 response: Stores new ETag from `ETag` header

---

### RefreshTokenInterceptor

Handles token refresh when receiving 401 Unauthorized responses.

```dart
RefreshTokenInterceptor(
  refreshToken: () async {
    final newToken = await authService.refresh();
    await secureStorage.write('access_token', newToken);
    return newToken;
  },
  shouldRefresh: (response) => response.statusCode == 401,
  maxRefreshAttempts: 1,
)
```

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `refreshToken` | `Future<String?> Function()` | required | Async function to refresh and return new token |
| `shouldRefresh` | `bool Function(Response)?` | status == 401 | When to trigger refresh |
| `maxRefreshAttempts` | `int` | `1` | Max refresh attempts per request |

**Flow:**
1. Request returns 401
2. RefreshTokenInterceptor calls `refreshToken()`
3. If successful, retries original request with new token
4. If refresh fails, propagates the error

---

## Configuring Interceptors

### At Initialization

```dart
fetchBloc.send(InitializeFetchEvent(
  config: FetchConfig(baseUrl: 'https://api.example.com'),
  interceptors: [
    TimingInterceptor(),
    LoggingInterceptor(logger: print),
    AuthInterceptor(tokenProvider: () async => token),
    RetryInterceptor(),
  ],
));
```

### Runtime Reconfiguration

Use `ReconfigureInterceptorsEvent` to change interceptors after initialization:

```dart
// Add auth when user logs in
fetchBloc.send(ReconfigureInterceptorsEvent(
  interceptors: [
    TimingInterceptor(),
    LoggingInterceptor(logger: print),
    AuthInterceptor(tokenProvider: () async => token),
  ],
));

// Remove auth when user logs out
fetchBloc.send(ReconfigureInterceptorsEvent(
  interceptors: [
    TimingInterceptor(),
    LoggingInterceptor(logger: print),
  ],
));
```

---

## Interceptor Priority

Interceptors execute in priority order. Lower values run first for `onRequest`, higher values run last for `onResponse`/`onError`.

| Interceptor | Priority | Reason |
|-------------|----------|--------|
| Logging | 0 | See raw request first |
| Auth | 10 | Add auth headers early |
| RefreshToken | 15 | Handle 401 before retry |
| Retry | 20 | Wrap request for retry logic |
| ETag | 30 | Add conditional headers |
| Metrics | 100 | Capture full timing last |

**Built-in priority constants:**

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

---

## Creating Custom Interceptors

Extend `FetchInterceptor` to create custom interceptors:

```dart
class CustomHeaderInterceptor extends FetchInterceptor {
  final String headerName;
  final String headerValue;

  CustomHeaderInterceptor({
    required this.headerName,
    required this.headerValue,
  });

  @override
  int get priority => 5;  // After logging, before auth

  @override
  Future<RequestOptions> onRequest(RequestOptions options) async {
    options.headers[headerName] = headerValue;
    return options;
  }

  @override
  Future<Response<dynamic>> onResponse(Response<dynamic> response) async {
    // Optionally modify response
    return response;
  }

  @override
  Future<dynamic> onError(DioException error) async {
    // Return error to propagate, or Response to recover
    return error;
  }
}
```

**Error recovery example:**

```dart
class FallbackInterceptor extends FetchInterceptor {
  @override
  Future<dynamic> onError(DioException error) async {
    if (error.type == DioExceptionType.connectionError) {
      // Return a fallback response instead of error
      return Response(
        requestOptions: error.requestOptions,
        statusCode: 200,
        data: {'fallback': true, 'cached': getCachedData()},
      );
    }
    return error;  // Propagate other errors
  }
}
```

---

## Common Patterns

### Development vs Production

```dart
List<FetchInterceptor> getInterceptors(bool isDev) {
  return [
    TimingInterceptor(),
    if (isDev) LoggingInterceptor(
      logger: print,
      logBody: true,
      logHeaders: true,
    ),
    AuthInterceptor(tokenProvider: () async => token),
    RetryInterceptor(maxRetries: isDev ? 1 : 3),
  ];
}
```

### Request Signing

```dart
class SignatureInterceptor extends FetchInterceptor {
  final String apiSecret;

  SignatureInterceptor(this.apiSecret);

  @override
  int get priority => 25;  // After auth, before request

  @override
  Future<RequestOptions> onRequest(RequestOptions options) async {
    final timestamp = DateTime.now().millisecondsSinceEpoch.toString();
    final signature = hmacSha256(
      '$timestamp${options.method}${options.path}',
      apiSecret,
    );
    options.headers['X-Timestamp'] = timestamp;
    options.headers['X-Signature'] = signature;
    return options;
  }
}
```

### Analytics/Metrics

```dart
class AnalyticsInterceptor extends FetchInterceptor {
  final AnalyticsService analytics;

  AnalyticsInterceptor(this.analytics);

  @override
  int get priority => InterceptorPriority.metrics;

  @override
  Future<Response<dynamic>> onResponse(Response<dynamic> response) async {
    final startTime = response.requestOptions.extra['_startTime'] as DateTime?;
    if (startTime != null) {
      final duration = DateTime.now().difference(startTime);
      analytics.trackApiCall(
        endpoint: response.requestOptions.path,
        method: response.requestOptions.method,
        statusCode: response.statusCode,
        durationMs: duration.inMilliseconds,
      );
    }
    return response;
  }
}
```
