---
layout: default
title: Home
nav_order: 1
---

# juice_network

A reactive HTTP client bloc for [Juice](https://pub.dev/packages/juice) applications with Dio integration, intelligent caching, request coalescing, and automatic retry.

{: .highlight }
juice_network automatically deduplicates concurrent identical requests, reducing network traffic and server load without any code changes.

## Key Features

| Feature | Description |
|---------|-------------|
| **Request Coalescing** | Automatic deduplication of concurrent identical requests |
| **Intelligent Caching** | Multiple cache policies for different use cases |
| **Automatic Retry** | Configurable retry with exponential backoff |
| **Request Tracking** | Real-time visibility into inflight requests |
| **Statistics** | Built-in metrics for monitoring and debugging |
| **Dio Integration** | Full access to Dio's powerful HTTP features |

## Installation

```yaml
dependencies:
  juice_network: ^0.9.0
```

## Quick Example

```dart
// Initialize
final fetchBloc = BlocScope.get<FetchBloc>();
await fetchBloc.send(InitializeFetchEvent(
  config: FetchConfig(
    baseUrl: 'https://api.example.com',
    defaultTtl: const Duration(minutes: 5),
  ),
));

// Make a request with caching
fetchBloc.send(GetEvent(
  url: '/posts',
  cachePolicy: CachePolicy.cacheFirst,
  decode: (json) => (json as List).map((e) => Post.fromJson(e)).toList(),
));
```

## Why juice_network?

### Problem: Duplicate Requests

In complex apps, multiple widgets or user interactions can trigger the same API request simultaneously:

- User rapidly taps a refresh button
- Multiple widgets mount and request the same data
- Navigation triggers overlapping data fetches

### Solution: Request Coalescing

juice_network automatically detects and coalesces duplicate inflight requests:

```dart
// 10 simultaneous requests to the same endpoint
for (var i = 0; i < 10; i++) {
  fetchBloc.send(GetEvent(url: '/posts/1'));
}

// Result: 1 network call, 9 coalesced
// All 10 callers get the same response
```

No configuration needed - it just works.

## Documentation

- [Getting Started](getting-started.html) - Installation and setup
- [Request Coalescing](coalescing.html) - How deduplication works
- [Cache Policies](caching.html) - Caching strategies explained
- [Interceptors](interceptors.html) - Authentication, logging, retry, and custom interceptors
- [Advanced Configuration](advanced-configuration.html) - Platform config, custom Dio, concurrency
- [API Reference](api.html) - Events, state, and configuration

## Part of the Juice Framework

juice_network is a companion package for [Juice](https://pub.dev/packages/juice), the reactive architecture framework for Flutter. It follows Juice patterns:

- **BlocScope** for lifecycle management
- **Events** for triggering operations
- **Use Cases** for business logic
- **Rebuild Groups** for efficient UI updates
