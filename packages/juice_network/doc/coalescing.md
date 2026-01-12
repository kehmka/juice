---
layout: default
title: Request Coalescing
nav_order: 3
---

# Request Coalescing

Request coalescing is one of juice_network's most powerful features. It automatically deduplicates concurrent identical requests, reducing network traffic and server load without requiring any code changes.

## The Problem

In complex Flutter applications, duplicate requests are common:

- **Rapid user interaction** - User taps a button multiple times quickly
- **Multiple widgets** - Several widgets mount simultaneously and request the same data
- **Navigation** - Screen transitions trigger overlapping data fetches
- **Pull-to-refresh** - User pulls to refresh while data is still loading

Without coalescing, each of these triggers a separate network call:

```
User taps 10 times rapidly:
  Request 1 -> Network -> Response
  Request 2 -> Network -> Response
  Request 3 -> Network -> Response
  ... (10 network calls total)
```

This wastes bandwidth, increases server load, and can cause rate limiting issues.

## The Solution

juice_network automatically detects when multiple requests target the same endpoint while a request is already inflight. Instead of making duplicate calls, subsequent requests **attach to the existing inflight request** and receive the same response.

```
User taps 10 times rapidly:
  Request 1 -> Network -> Response
  Request 2 -> (attached to Request 1) -> Same Response
  Request 3 -> (attached to Request 1) -> Same Response
  ... (1 network call, 9 coalesced)
```

## How It Works

### Request Key Generation

Each request is assigned a unique key based on:
- HTTP method (GET, POST, etc.)
- URL path
- Query parameters
- Request body (for POST/PUT/PATCH)

Requests with identical keys are candidates for coalescing.

### Coalescing Logic

```
┌─────────────────────────────────────────────────────────────┐
│                    New Request Arrives                       │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
                 ┌────────────────────────┐
                 │ Is identical request   │
                 │ already inflight?      │
                 └────────────────────────┘
                      │           │
                     YES          NO
                      │           │
                      ▼           ▼
            ┌──────────────┐  ┌──────────────┐
            │ Attach to    │  │ Make new     │
            │ existing     │  │ network call │
            │ request      │  │              │
            └──────────────┘  └──────────────┘
                      │           │
                      └─────┬─────┘
                            ▼
                ┌──────────────────────┐
                │ Response received    │
                │ All callers notified │
                └──────────────────────┘
```

### Automatic Behavior

Coalescing happens automatically - no configuration needed:

```dart
// All 10 of these will be coalesced into 1 network call
for (var i = 0; i < 10; i++) {
  fetchBloc.send(GetEvent(
    url: '/posts/1',
    cachePolicy: CachePolicy.networkOnly,
  ));
}
```

## Demo: Fire Burst

The example app includes a "Coalesce" screen that demonstrates this feature:

1. **Fire Request** - Tap rapidly to see coalescing with manual taps
2. **Fire Burst (10x)** - Fires 10 simultaneous requests with one tap

When you tap "Fire Burst":
- 10 requests are sent simultaneously
- 1 actual network call is made
- 9 requests are coalesced
- All 10 callers receive the same response

## Tracking Coalesced Requests

### Statistics

Access coalescing metrics via `FetchState.stats`:

```dart
final stats = fetchBloc.state.stats;

print('Total requests: ${stats.totalRequests}');
print('Coalesced: ${stats.coalescedCount}');
print('Actual network calls: ${stats.totalRequests - stats.coalescedCount}');
```

### Real-time Monitoring

The stats are updated in real-time. Use rebuild groups to react to changes:

```dart
class StatsWidget extends StatelessJuiceWidget<FetchBloc> {
  StatsWidget({super.groups = const {'fetch:stats'}});

  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    final stats = bloc.state.stats;
    return Text('Coalesced: ${stats.coalescedCount}');
  }
}
```

## When Coalescing Applies

Coalescing applies when:

| Condition | Applies |
|-----------|---------|
| Same URL + method + params | Yes |
| Different URLs | No |
| Same URL, different query params | No |
| POST with different body | No |
| Request already completed | No |
| First request still inflight | Yes |

## Benefits

### Reduced Server Load

Your API receives fewer requests:

```
Without coalescing: 100 taps = 100 API calls
With coalescing:    100 taps = ~10 API calls (depends on timing)
```

### Lower Bandwidth

Only one request/response travels over the network, regardless of how many callers requested it.

### Consistent Data

All consumers receive exactly the same response data, eliminating potential race conditions or stale data issues.

### No Code Changes

Coalescing is automatic. You don't need to:
- Add debouncing logic
- Implement request deduplication
- Track inflight requests manually
- Coordinate between widgets

## Best Practices

### Use networkOnly for Coalesce Testing

To clearly observe coalescing, use `CachePolicy.networkOnly`:

```dart
fetchBloc.send(GetEvent(
  url: '/posts/1',
  cachePolicy: CachePolicy.networkOnly, // Bypass cache
));
```

With `cacheFirst`, cached responses return immediately and may not trigger coalescing.

### Fire Requests Without Awaiting

To maximize coalescing, fire requests without `await`:

```dart
// Good - requests fire simultaneously
for (var i = 0; i < 10; i++) {
  fetchBloc.send(GetEvent(url: '/data')); // No await
}

// Less effective - requests are serialized
for (var i = 0; i < 10; i++) {
  await fetchBloc.send(GetEvent(url: '/data')); // Await waits for completion
}
```

### Monitor with Statistics

Track coalescing effectiveness to understand your app's request patterns:

```dart
void logStats() {
  final stats = fetchBloc.state.stats;
  final total = stats.totalRequests;
  final coalesced = stats.coalescedCount;
  final saved = total > 0 ? (coalesced / total * 100).toStringAsFixed(1) : '0';

  print('Saved $saved% of network calls via coalescing');
}
```

## Comparison to Other Approaches

| Approach | Pros | Cons |
|----------|------|------|
| **Coalescing** | Automatic, no code changes | Only works for inflight requests |
| **Debouncing** | Delays rapid inputs | Adds latency, manual implementation |
| **Throttling** | Limits request rate | May miss important updates |
| **Manual dedup** | Full control | Complex, error-prone |

juice_network's coalescing works alongside caching for comprehensive request optimization.
