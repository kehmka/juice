---
layout: default
title: Error Handling
nav_order: 6
---

# Error Handling

juice_network provides typed errors that make it easy to handle different failure scenarios appropriately.

## Error Hierarchy

```
FetchError (abstract)
├── NetworkError        - Connection/network issues
├── TimeoutError        - Request timeouts
├── HttpError           - HTTP error responses
│   ├── ClientError     - 4xx errors
│   └── ServerError     - 5xx errors
├── CancelledError      - Request was cancelled
└── DecodeError         - Response parsing failed
```

All errors extend `FetchError` and include:
- `message` - Human-readable description
- `requestKey` - The request that failed
- `cause` - Original exception (if any)
- `stackTrace` - Stack trace for debugging

---

## Error Types

### NetworkError

Connection and network-level failures.

```dart
class NetworkError extends FetchError {
  final String message;
  final RequestKey requestKey;
  final Object? cause;
  final StackTrace? stackTrace;
}
```

**Common causes:**
- No internet connection
- DNS resolution failed
- Server unreachable
- SSL/TLS handshake failed

**Factory constructor:**

```dart
NetworkError.noConnection({
  required RequestKey requestKey,
  Object? cause,
  StackTrace? stackTrace,
})
```

**Handling example:**

```dart
try {
  await fetchBloc.send(GetEvent(url: '/data'));
} catch (e) {
  if (e is NetworkError) {
    showSnackbar('No internet connection. Please try again.');
  }
}
```

---

### TimeoutError

Request exceeded configured timeout limits.

```dart
class TimeoutError extends FetchError {
  final TimeoutType type;  // connect, send, or receive
  final Duration timeout;
  final RequestKey requestKey;
}
```

**Timeout types:**

| Type | Description | Config Property |
|------|-------------|-----------------|
| `connect` | Connection establishment timeout | `connectTimeout` |
| `send` | Request body upload timeout | `sendTimeout` |
| `receive` | Response download timeout | `receiveTimeout` |

**Factory constructors:**

```dart
TimeoutError.connect({required Duration timeout, required RequestKey requestKey})
TimeoutError.send({required Duration timeout, required RequestKey requestKey})
TimeoutError.receive({required Duration timeout, required RequestKey requestKey})
```

**Handling example:**

```dart
if (e is TimeoutError) {
  switch (e.type) {
    case TimeoutType.connect:
      showSnackbar('Server is not responding. Try again later.');
      break;
    case TimeoutType.receive:
      showSnackbar('Download is taking too long. Check your connection.');
      break;
    default:
      showSnackbar('Request timed out.');
  }
}
```

---

### HttpError

Base class for HTTP error responses (non-2xx status codes).

```dart
class HttpError extends FetchError {
  final int statusCode;
  final String message;
  final dynamic responseBody;
  final Map<String, List<String>>? responseHeaders;
  final RequestKey requestKey;
}
```

**Properties:**

| Property | Type | Description |
|----------|------|-------------|
| `statusCode` | `int` | HTTP status code |
| `responseBody` | `dynamic` | Parsed response body (if any) |
| `responseHeaders` | `Map?` | Response headers |

---

### ClientError

HTTP 4xx client errors (bad request, unauthorized, not found, etc.).

```dart
class ClientError extends HttpError {
  // Inherits all HttpError properties
}
```

**Common status codes:**

| Code | Meaning | Typical Action |
|------|---------|----------------|
| 400 | Bad Request | Fix request parameters |
| 401 | Unauthorized | Redirect to login |
| 403 | Forbidden | Show access denied |
| 404 | Not Found | Show "not found" UI |
| 409 | Conflict | Handle data conflict |
| 422 | Unprocessable | Show validation errors |
| 429 | Too Many Requests | Implement backoff |

**Handling example:**

```dart
if (e is ClientError) {
  switch (e.statusCode) {
    case 401:
      authBloc.send(LogoutEvent());
      navigator.pushReplacementNamed('/login');
      break;
    case 404:
      showSnackbar('Item not found.');
      break;
    case 422:
      // Parse validation errors from response body
      final errors = e.responseBody['errors'] as Map<String, dynamic>;
      showValidationErrors(errors);
      break;
    default:
      showSnackbar('Request failed: ${e.message}');
  }
}
```

---

### ServerError

HTTP 5xx server errors.

```dart
class ServerError extends HttpError {
  // Inherits all HttpError properties
}
```

**Common status codes:**

| Code | Meaning | Typical Action |
|------|---------|----------------|
| 500 | Internal Server Error | Show generic error, log for debugging |
| 502 | Bad Gateway | Retry after delay |
| 503 | Service Unavailable | Show maintenance message |
| 504 | Gateway Timeout | Retry with backoff |

**Handling example:**

```dart
if (e is ServerError) {
  if (e.statusCode == 503) {
    showMaintenanceScreen();
  } else {
    showSnackbar('Server error. Our team has been notified.');
    errorReporter.report(e);
  }
}
```

---

### CancelledError

Request was cancelled (by user, scope cleanup, or programmatically).

```dart
class CancelledError extends FetchError {
  final String? reason;
  final RequestKey requestKey;
}
```

**Common cancellation reasons:**
- User navigated away (scope cancellation)
- New request superseded this one
- Explicit `CancelRequestEvent` sent
- Bloc closed

**Handling example:**

```dart
if (e is CancelledError) {
  // Usually safe to ignore - user navigated away
  debugPrint('Request cancelled: ${e.reason}');
}
```

---

### DecodeError

Response parsing/decoding failed.

```dart
class DecodeError extends FetchError {
  final String message;
  final dynamic rawResponse;
  final RequestKey requestKey;
  final Object? cause;
}
```

**Common causes:**
- Invalid JSON
- Type mismatch (expected object, got array)
- Missing required fields
- Custom decode function threw

**Handling example:**

```dart
if (e is DecodeError) {
  debugPrint('Failed to parse response: ${e.rawResponse}');
  showSnackbar('Received unexpected data format.');
}
```

---

## Accessing Errors in State

The most recent error is stored in `FetchState.lastError`:

```dart
class ErrorWidget extends StatelessJuiceWidget<FetchBloc> {
  ErrorWidget() : super(groups: const {'fetch:error'});

  @override
  Widget onBuild(BuildContext context, FetchState state) {
    final error = state.lastError;
    if (error == null) return const SizedBox.shrink();

    return ErrorBanner(
      message: _getErrorMessage(error),
      onDismiss: () => bloc.send(ClearLastErrorEvent()),
    );
  }

  String _getErrorMessage(Object error) {
    if (error is NetworkError) return 'No internet connection';
    if (error is TimeoutError) return 'Request timed out';
    if (error is ClientError) return 'Request failed: ${error.statusCode}';
    if (error is ServerError) return 'Server error. Try again later.';
    if (error is CancelledError) return '';  // Don't show
    return 'An error occurred';
  }
}
```

---

## Comprehensive Error Handling

Pattern for handling all error types:

```dart
void handleFetchError(FetchError error) {
  switch (error) {
    case NetworkError():
      _showNetworkError();
      break;

    case TimeoutError(type: final type):
      _showTimeoutError(type);
      break;

    case ClientError(statusCode: 401):
      _handleUnauthorized();
      break;

    case ClientError(statusCode: 404):
      _showNotFound();
      break;

    case ClientError(statusCode: final code, responseBody: final body):
      _showClientError(code, body);
      break;

    case ServerError(statusCode: 503):
      _showMaintenance();
      break;

    case ServerError():
      _showServerError();
      _reportToErrorService(error);
      break;

    case CancelledError():
      // Ignore - user navigated away
      break;

    case DecodeError():
      _showParseError();
      _reportToErrorService(error);
      break;
  }
}
```

---

## Stale-While-Error Pattern

Use `allowStaleOnError` to serve cached data when network fails:

```dart
fetchBloc.send(GetEvent(
  url: '/posts',
  cachePolicy: CachePolicy.networkFirst,
  allowStaleOnError: true,  // Return stale cache on error
));
```

This prevents errors from showing to users when cached data is available, even if expired.

---

## Error Statistics

Track error rates via `FetchState.stats`:

```dart
final stats = fetchBloc.state.stats;
print('Success rate: ${stats.successRate}%');
print('Failures: ${stats.failureCount}');
print('Retries: ${stats.retryCount}');
```

Reset statistics:

```dart
fetchBloc.send(ResetStatsEvent());
```
