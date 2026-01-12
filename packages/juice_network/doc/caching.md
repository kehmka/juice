---
layout: default
title: Cache Policies
nav_order: 4
---

# Cache Policies

juice_network provides five caching strategies to optimize network usage for different scenarios.

## Available Policies

### networkFirst

**Default policy.** Try the network first; fall back to cache if the network fails.

```dart
fetchBloc.send(GetEvent(
  url: '/posts',
  cachePolicy: CachePolicy.networkFirst,
));
```

**Best for:**
- Data that should be fresh when possible
- APIs with reasonable latency
- Content that changes frequently

**Behavior:**
1. Make network request
2. If successful, cache and return response
3. If failed, return cached data (if available)
4. If no cache, propagate error

---

### cacheFirst

Return cached data if available; only fetch from network if cache is empty or expired.

```dart
fetchBloc.send(GetEvent(
  url: '/posts',
  cachePolicy: CachePolicy.cacheFirst,
  ttl: const Duration(hours: 1),
));
```

**Best for:**
- Static or rarely-changing data
- Reducing network calls
- Offline-first apps
- Images, configuration, reference data

**Behavior:**
1. Check cache for valid (non-expired) entry
2. If found, return immediately
3. If not found or expired, fetch from network
4. Cache and return response

---

### staleWhileRevalidate

Return cached data immediately (even if stale), then refresh in the background.

```dart
fetchBloc.send(GetEvent(
  url: '/feed',
  cachePolicy: CachePolicy.staleWhileRevalidate,
));
```

**Best for:**
- News feeds, social media timelines
- Data where showing something is better than loading
- User-perceived performance optimization

**Behavior:**
1. Return cached data immediately (if available)
2. Simultaneously fetch from network
3. Update cache with fresh data
4. UI rebuilds with new data via stream

---

### cacheOnly

Only use cached data. Never make a network request.

```dart
fetchBloc.send(GetEvent(
  url: '/offline-data',
  cachePolicy: CachePolicy.cacheOnly,
));
```

**Best for:**
- Offline mode
- Displaying previously-loaded data
- Reducing battery/data usage

**Behavior:**
1. Check cache
2. If found, return cached data
3. If not found, emit failure

---

### networkOnly

Always fetch from network. Never read from or write to cache.

```dart
fetchBloc.send(GetEvent(
  url: '/realtime-data',
  cachePolicy: CachePolicy.networkOnly,
));
```

**Best for:**
- Real-time data (stock prices, live scores)
- Sensitive data that shouldn't be cached
- Testing/debugging
- Request coalescing demonstrations

**Behavior:**
1. Make network request
2. Return response (no caching)

---

## Policy Comparison

| Policy | Network | Cache Read | Cache Write | Offline Support |
|--------|---------|------------|-------------|-----------------|
| `networkFirst` | Always tried | Fallback | Yes | Yes (stale) |
| `cacheFirst` | If no cache | First | Yes | Yes |
| `staleWhileRevalidate` | Background | Immediate | Yes | Yes (stale) |
| `cacheOnly` | Never | Only | No | Yes |
| `networkOnly` | Always | Never | No | No |

## Cache TTL

Set how long cached data remains valid:

```dart
// Per-request TTL
fetchBloc.send(GetEvent(
  url: '/posts',
  cachePolicy: CachePolicy.cacheFirst,
  ttl: const Duration(minutes: 30),
));

// Default TTL in config
FetchConfig(
  defaultTtl: const Duration(minutes: 5),
);
```

## Cache Management

### Clear All Cache

```dart
fetchBloc.send(ClearCacheEvent());
```

### Cache Statistics

```dart
final stats = fetchBloc.state.stats;
final cacheStats = fetchBloc.state.cacheStats;

print('Cache hits: ${stats.cacheHits}');
print('Cache misses: ${stats.cacheMisses}');
print('Hit rate: ${stats.hitRate}%');
print('Entries: ${cacheStats.entryCount}');
print('Size: ${cacheStats.totalBytes} bytes');
```

## Choosing the Right Policy

### Decision Guide

```
Is the data real-time/sensitive?
  └─ Yes → networkOnly

Can you show stale data?
  └─ No → networkFirst
  └─ Yes → Is immediate display important?
           └─ Yes → staleWhileRevalidate
           └─ No → cacheFirst

Is offline support critical?
  └─ Yes → cacheFirst or staleWhileRevalidate
  └─ No → networkFirst
```

### Common Patterns

| Data Type | Recommended Policy |
|-----------|-------------------|
| User profile | networkFirst |
| Product catalog | cacheFirst |
| News feed | staleWhileRevalidate |
| Stock prices | networkOnly |
| App configuration | cacheFirst (long TTL) |
| Search results | networkOnly |
| Chat messages | networkFirst |
| Static images | cacheFirst (very long TTL) |

## Interaction with Coalescing

Cache policies work alongside request coalescing:

1. **cacheFirst** - If cache hit, returns immediately (no coalescing needed)
2. **networkOnly** - Best for observing coalescing behavior
3. **staleWhileRevalidate** - Returns cache, background fetch may coalesce
4. **networkFirst** - Network request may coalesce if duplicate

For testing coalescing, use `networkOnly` to ensure requests hit the network.
