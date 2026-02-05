---
layout: default
title: Getting Started
nav_order: 2
---

# Getting Started

This guide walks you through setting up juice_network in your Flutter application.

## Prerequisites

- Flutter 3.0+
- [juice](https://pub.dev/packages/juice) package
- [juice_storage](https://pub.dev/packages/juice_storage) package (for caching)

## Installation

Add the dependencies to your `pubspec.yaml`:

```yaml
dependencies:
  juice: ^1.2.0
  juice_network: ^0.9.0
  juice_storage: ^1.0.0
```

Then run:

```bash
flutter pub get
```

## Setup

### 1. Register the Blocs

juice_network requires a `StorageBloc` for caching. Register both blocs at app startup:

```dart
import 'package:juice/juice.dart';
import 'package:juice_network/juice_network.dart';
import 'package:juice_storage/juice_storage.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Register StorageBloc first (required for caching)
  BlocScope.register<StorageBloc>(
    () => StorageBloc(config: const StorageConfig(
      prefsKeyPrefix: 'myapp_',
      hiveBoxesToOpen: ['_fetch_cache'],
    )),
    lifecycle: BlocLifecycle.permanent,
  );

  // Initialize storage
  final storageBloc = BlocScope.get<StorageBloc>();
  await storageBloc.initialize();

  // Register FetchBloc
  BlocScope.register<FetchBloc>(
    () => FetchBloc(storageBloc: storageBloc),
    lifecycle: BlocLifecycle.permanent,
  );

  runApp(MyApp());
}
```

### 2. Initialize FetchBloc

Before making requests, initialize FetchBloc with your configuration:

```dart
final fetchBloc = BlocScope.get<FetchBloc>();

await fetchBloc.send(InitializeFetchEvent(
  config: FetchConfig(
    baseUrl: 'https://api.example.com',
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 10),
    defaultTtl: const Duration(minutes: 5),
    defaultCachePolicy: CachePolicy.networkFirst,
    headers: {
      'Content-Type': 'application/json',
    },
  ),
));
```

### 3. Make Your First Request

```dart
// Simple GET request
fetchBloc.send(GetEvent(
  url: '/users/1',
  decode: (json) => User.fromJson(json),
));
```

## Configuration Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `baseUrl` | `String` | required | Base URL for all requests |
| `connectTimeout` | `Duration` | 30s | Connection timeout |
| `receiveTimeout` | `Duration` | 30s | Response timeout |
| `sendTimeout` | `Duration` | 30s | Request send timeout |
| `defaultTtl` | `Duration` | 5min | Default cache TTL |
| `defaultCachePolicy` | `CachePolicy` | networkFirst | Default caching strategy |
| `maxRetries` | `int` | 3 | Max retry attempts |
| `headers` | `Map<String, String>` | {} | Default headers |

## Making Requests

### GET Request

```dart
fetchBloc.send(GetEvent(
  url: '/posts',
  queryParameters: {'page': '1', 'limit': '10'},
  cachePolicy: CachePolicy.cacheFirst,
  ttl: const Duration(minutes: 10),
  decode: (json) => (json as List).map((e) => Post.fromJson(e)).toList(),
));
```

### POST Request

```dart
fetchBloc.send(PostEvent(
  url: '/posts',
  body: {
    'title': 'My Post',
    'body': 'Post content here',
    'userId': 1,
  },
  decode: (json) => Post.fromJson(json),
));
```

### PUT Request

```dart
fetchBloc.send(PutEvent(
  url: '/posts/1',
  body: {'title': 'Updated Title'},
  decode: (json) => Post.fromJson(json),
));
```

### DELETE Request

```dart
fetchBloc.send(DeleteEvent(
  url: '/posts/1',
));
```

## Handling Responses

### Using JuiceAsyncBuilder

```dart
class PostsList extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final fetchBloc = BlocScope.get<FetchBloc>();

    return JuiceAsyncBuilder<StreamStatus<FetchState>>(
      stream: fetchBloc.stream,
      initial: StreamStatus.updating(fetchBloc.state, fetchBloc.state, null),
      builder: (context, status) {
        if (status is WaitingStatus) {
          return const CircularProgressIndicator();
        }

        if (status is FailureStatus) {
          return Text('Error: ${fetchBloc.state.lastError}');
        }

        // Access your decoded data from wherever you stored it
        return ListView.builder(
          itemCount: posts.length,
          itemBuilder: (context, index) => PostTile(post: posts[index]),
        );
      },
    );
  }
}
```

### Checking Request Status

```dart
final state = fetchBloc.state;

// Check if any requests are inflight
if (state.inflightCount > 0) {
  print('${state.inflightCount} requests in progress');
}

// Check specific request status
final requestKey = 'GET:/posts/1';
final status = state.activeRequests[requestKey];
if (status != null) {
  print('Phase: ${status.phase}');
  print('Attempt: ${status.attempt}');
}
```

## Next Steps

- Learn about [Request Coalescing](coalescing.html) to understand automatic deduplication
- Explore [Cache Policies](caching.html) for different caching strategies
- Check the [API Reference](api.html) for all available events and options
