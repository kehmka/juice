# juice_network

A reactive HTTP client bloc for [Juice](https://pub.dev/packages/juice) applications with Dio integration, intelligent caching, request coalescing, and automatic retry.

[![pub package](https://img.shields.io/pub/v/juice_network.svg)](https://pub.dev/packages/juice_network)
[![License: MIT](https://img.shields.io/badge/license-MIT-purple.svg)](LICENSE)

## Features

- **Request Coalescing** - Automatically deduplicates concurrent identical requests, reducing network traffic and server load
- **Intelligent Caching** - Multiple cache policies (networkFirst, cacheFirst, staleWhileRevalidate, cacheOnly, networkOnly)
- **Automatic Retry** - Configurable retry with exponential backoff for failed requests
- **Request Tracking** - Real-time visibility into inflight requests and their status
- **Statistics** - Built-in metrics for cache hits, success rates, response times, and more
- **Dio Integration** - Full access to Dio's powerful HTTP features
- **Auth Isolation** - User-specific cache/coalescing isolation for multi-user scenarios
- **Concurrency Limiting** - Queue-based request throttling to prevent server overload
- **Request Scoping** - Group and cancel related requests together

## Installation

```yaml
dependencies:
  juice_network: ^0.9.1
```

## Quick Start

### 1. Initialize the Blocs

```dart
import 'package:juice/juice.dart';
import 'package:juice_network/juice_network.dart';
import 'package:juice_storage/juice_storage.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Register StorageBloc (required for caching)
  BlocScope.register<StorageBloc>(
    () => StorageBloc(config: const StorageConfig(
      hiveBoxesToOpen: [CacheManager.cacheBoxName],
    )),
    lifecycle: BlocLifecycle.permanent,
  );

  final storageBloc = BlocScope.get<StorageBloc>();
  await storageBloc.initialize();

  // Register FetchBloc
  BlocScope.register<FetchBloc>(
    () => FetchBloc(storageBloc: storageBloc),
    lifecycle: BlocLifecycle.permanent,
  );

  // Initialize with configuration
  final fetchBloc = BlocScope.get<FetchBloc>();
  await fetchBloc.send(InitializeFetchEvent(
    config: FetchConfig(
      baseUrl: 'https://api.example.com',
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
      defaultTtl: const Duration(minutes: 5),
    ),
  ));

  runApp(MyApp());
}
```

### 2. Make Requests

```dart
// Simple GET request
fetchBloc.send(GetEvent(
  url: '/users/1',
  decode: (json) => User.fromJson(json),
));

// With cache policy
fetchBloc.send(GetEvent(
  url: '/posts',
  cachePolicy: CachePolicy.cacheFirst,
  ttl: const Duration(minutes: 10),
  decode: (json) => (json as List).map((e) => Post.fromJson(e)).toList(),
));

// POST request
fetchBloc.send(PostEvent(
  url: '/posts',
  body: {'title': 'Hello', 'body': 'World'},
  decode: (json) => Post.fromJson(json),
));
```

### 3. React to State Changes

```dart
class PostsWidget extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final fetchBloc = BlocScope.get<FetchBloc>();

    return JuiceAsyncBuilder<StreamStatus<FetchState>>(
      stream: fetchBloc.stream,
      initial: StreamStatus.updating(fetchBloc.state, fetchBloc.state, null),
      builder: (context, status) {
        if (status is WaitingStatus) {
          return CircularProgressIndicator();
        }
        if (status is FailureStatus) {
          return Text('Error: ${fetchBloc.state.lastError}');
        }
        return Text('Loaded successfully');
      },
    );
  }
}
```

## Request Coalescing

One of juice_network's key features is **request coalescing** - automatic deduplication of concurrent identical requests.

### How It Works

When multiple parts of your app request the same resource simultaneously:

1. The first request goes to the network
2. Subsequent identical requests **attach to the existing inflight request**
3. All callers receive the same response when it arrives
4. Only **one network call** is made

### Example

```dart
// User rapidly taps a button, or multiple widgets request the same data
for (var i = 0; i < 10; i++) {
  fetchBloc.send(GetEvent(
    url: '/posts/1',
    cachePolicy: CachePolicy.networkOnly,
  ));
}

// Result: 1 network call, 9 coalesced requests
// All 10 callers get the same response
```

### Benefits

- **Reduced server load** - Prevents duplicate requests from hammering your API
- **Lower bandwidth usage** - Only one request travels over the network
- **Consistent data** - All consumers receive the same response
- **No code changes needed** - Coalescing happens automatically

### Statistics

Track coalescing effectiveness via `FetchState.stats`:

```dart
final stats = fetchBloc.state.stats;
print('Total requests: ${stats.totalRequests}');
print('Coalesced: ${stats.coalescedCount}');
```

## Cache Policies

| Policy | Behavior |
|--------|----------|
| `networkFirst` | Try network, fall back to cache on failure |
| `cacheFirst` | Use cache if available, otherwise fetch from network |
| `staleWhileRevalidate` | Return cached data immediately, refresh in background |
| `cacheOnly` | Only use cached data, fail if not available |
| `networkOnly` | Always fetch from network, never cache |

```dart
fetchBloc.send(GetEvent(
  url: '/data',
  cachePolicy: CachePolicy.staleWhileRevalidate,
  ttl: const Duration(hours: 1),
));
```

## Configuration

```dart
FetchConfig(
  baseUrl: 'https://api.example.com',
  connectTimeout: const Duration(seconds: 30),
  receiveTimeout: const Duration(seconds: 30),
  sendTimeout: const Duration(seconds: 30),
  defaultTtl: const Duration(minutes: 5),
  defaultCachePolicy: CachePolicy.networkFirst,
  maxRetries: 3,
  headers: {'Authorization': 'Bearer token'},
)
```

## Events

| Event | Description |
|-------|-------------|
| `InitializeFetchEvent` | Initialize with configuration |
| `GetEvent` | HTTP GET request |
| `PostEvent` | HTTP POST request |
| `PutEvent` | HTTP PUT request |
| `PatchEvent` | HTTP PATCH request |
| `DeleteEvent` | HTTP DELETE request |
| `HeadEvent` | HTTP HEAD request |
| `InvalidateCacheEvent` | Invalidate cache by key, pattern, or namespace |
| `ClearCacheEvent` | Clear all cached responses (or by namespace) |
| `CleanupExpiredCacheEvent` | Remove expired cache entries |
| `PruneCacheEvent` | Prune cache to target size |
| `CancelRequestEvent` | Cancel a specific request |
| `CancelScopeEvent` | Cancel all requests in a scope |
| `CancelAllEvent` | Cancel all inflight requests |
| `ResetFetchEvent` | Reset FetchBloc to baseline state |
| `ResetStatsEvent` | Reset statistics counters |
| `ReconfigureInterceptorsEvent` | Change interceptors at runtime |

## Rebuild Groups

Subscribe to specific state changes:

- `fetch:inflight` - Inflight request count changes
- `fetch:stats` - Statistics updates
- `fetch:cache` - Cache state changes
- `fetch:request:{METHOD}:{path}` - Specific request status

## Statistics

Access detailed metrics:

```dart
final stats = fetchBloc.state.stats;

// Request metrics
stats.totalRequests
stats.successCount
stats.failureCount
stats.successRate
stats.retryCount
stats.coalescedCount

// Cache metrics
stats.cacheHits
stats.cacheMisses
stats.hitRate

// Performance
stats.avgResponseTimeMs
stats.bytesReceived
stats.bytesSent
```

## Example App

See the [example](example/) directory for a complete demo app showcasing:

- Different cache policies
- Request coalescing demonstration
- Real-time statistics dashboard

## License

MIT License - see [LICENSE](LICENSE) for details.
