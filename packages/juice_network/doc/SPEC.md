# juice_network Specification

> **Status:** Draft v1.3 (pre-freeze)
> **Package:** `juice_network`
> **Primary Bloc:** `FetchBloc`

## Overview

**juice_network** provides a foundation bloc for remote I/O operations. While StorageBloc solves "local truth," FetchBloc solves "field truth."

---

## Dependencies

| Package | Dependency | Purpose |
|---------|------------|---------|
| `juice` | Required | Core bloc infrastructure |
| `juice` | Required | `LifecycleBloc` for automatic scope-based cancellation |
| `juice_storage` | Required | Cache persistence via `StorageBloc` |
| `dio` | Required | HTTP transport |

**Prerequisite:** `LifecycleBloc` must be registered before `FetchBloc`:

```dart
void main() {
  // 1. Register LifecycleBloc first (core juice)
  BlocScope.register<LifecycleBloc>(
    () => LifecycleBloc(),
    lifecycle: BlocLifecycle.permanent,
  );

  // 2. Then register FetchBloc
  BlocScope.register<FetchBloc>(
    () => FetchBloc(),
    lifecycle: BlocLifecycle.permanent,
  );

  runApp(MyApp());
}
```

---

## Why Use FetchBloc?

> **Dio is a transport client. FetchBloc is a remote-state contract.**
>
> It makes network behavior deterministic, deduped, cancellable, cache-safe, typed, inspectable, and consistent across the whole app.

---

### The 5 Problems With "Just Dio"

Every team without a network foundation ends up with:

```dart
// Scattered across your codebase:
class UserService {
  final dio = Dio();  // Where's the config?

  Future<User> getUser(int id) async {
    try {
      final response = await dio.get('/users/$id');  // No caching
      return User.fromJson(response.data);           // No error typing
    } catch (e) {
      throw Exception('Failed to load user');        // String soup
    }
  }
}

class ProfileScreen extends StatefulWidget {
  // Loading state here...
}

class SettingsScreen extends StatefulWidget {
  // Different loading state here...
  // Different error handling here...
  // Forgot to cancel on dispose...
}
```

**This creates real bugs:**

| # | Problem | What Goes Wrong |
|---|---------|-----------------|
| 1 | **Request storms** | 10 widgets mount → 10 identical API calls. User taps fast → race conditions. |
| 2 | **Inconsistent cache** | "Sometimes it's cached, sometimes not." No TTL. No policy. |
| 3 | **Error soup** | `catch (e) { throw Exception('Failed') }` — no type info, no retry semantics. |
| 4 | **Cancellation leaks** | Screen disposed → response arrives → `setState` on unmounted widget. |
| 5 | **No observability** | "What requests are in flight right now?" No inspector, no stats. |

### The 6 Things FetchBloc Adds

| # | Capability | What It Does |
|---|------------|--------------|
| 1 | **Deterministic identity** | `RequestKey` canonicalizes URL + body + headers → stable cache/dedupe keys |
| 2 | **Coalescing** | 10 callers, same key → 1 network call, 10 completers resolved |
| 3 | **Safe cache** | Raw bytes stored (decoder bugs don't poison cache), TTL, Cache-Control respected |
| 4 | **Typed errors** | `NetworkError`, `HttpError`, `DecodeError`, `CancelledError` — not string soup |
| 5 | **Retry/refresh correctness** | Idempotent-only retry, singleflight token refresh, exponential backoff |
| 6 | **Juice-native observability** | `StatelessJuiceWidget` with rebuild groups — one pattern everywhere |

```dart
// One place, consistent behavior:
final event = GetEvent<User>(
  url: '/users/$id',
  decode: User.fromJson,
  cachePolicy: CachePolicy.staleWhileRevalidate,
  scope: 'profile-screen',
);
fetchBloc.send(event);
final user = await event.result;
```

**And in your UI:**

```dart
// Any widget, anywhere - same pattern via StatelessJuiceWidget
class UserProfileWidget extends StatelessJuiceWidget<FetchBloc> {
  final RequestKey userKey;

  UserProfileWidget({
    super.key,
    required this.userKey,
  }) : super(groups: {'fetch:request:${userKey.canonical}'});

  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    final requestStatus = bloc.state.activeRequests[userKey];
    if (requestStatus?.phase == RequestPhase.inflight) {
      return LoadingSpinner();
    }
    // ...
  }
}
```

### Side-by-Side Comparison

| Concern | Just Dio | FetchBloc |
|---------|----------|-----------|
| **Caching** | DIY or nothing | `CachePolicy.cacheFirst` + TTL |
| **Deduplication** | Hope widgets don't race | Automatic coalescing by `RequestKey` |
| **Cancellation** | `CancelToken` scattered, often forgotten | `CancelScopeEvent(scope: 'screen')` on dispose |
| **Loading state** | `setState` in every screen | `StatelessJuiceWidget` with `fetch:inflight` group |
| **Error handling** | `try/catch` with strings | Typed `FetchError` hierarchy |
| **Retry logic** | Copy-paste exponential backoff | Built-in, respects idempotency |
| **Auth headers** | Interceptor you hope is attached | `AuthInterceptor` with singleflight refresh |
| **Observability** | `print()` statements | Event log, inspector, stats |
| **Testing** | Mock Dio, hope it's right | Mock events, assert state |

### Concrete Benefits

#### 1. No More Request Storms

```dart
// 10 widgets request same user simultaneously
for (var i = 0; i < 10; i++) {
  fetchBloc.send(GetEvent(url: '/users/123'));
}
// Result: 1 network call, 10 widgets get the same response
```

#### 2. Automatic Cancellation via LifecycleBloc

FetchBloc subscribes to `LifecycleBloc.notifications` for automatic request cancellation when feature scopes end.

```dart
/// Feature flow with automatic request cancellation
class ProfileFlow {
  final scope = FeatureScope('profile');

  void start() {
    BlocScope.register<ProfileBloc>(
      () => ProfileBloc(),
      lifecycle: BlocLifecycle.feature,
      scope: scope,
    );
  }

  Future<void> complete() async {
    // 1. scope.end() → LifecycleBloc publishes ScopeEndingNotification
    // 2. FetchBloc (subscribed) receives event → cancels 'profile' requests
    // 3. Blocs disposed after cleanup completes
    await scope.end();
  }
}

/// Requests tagged with scope are auto-cancelled
class ProfileBloc extends JuiceBloc<ProfileState> {
  ProfileBloc() : super(ProfileState.initial()) {
    _fetchUser();
  }

  void _fetchUser() {
    final fetchBloc = BlocScope.get<FetchBloc>();
    fetchBloc.send(GetEvent<User>(
      url: '/api/user',
      scope: 'profile',  // Tagged → auto-cancelled when scope ends
      decode: User.fromJson,
    ));
  }
}
```

**Flow:**
```
User navigates away
  → ProfileFlow.complete()
    → scope.end()
      → LifecycleBloc.send(EndScopeEvent)
        → LifecycleBloc publishes ScopeEndingNotification('profile')
          → FetchBloc receives notification, cancels requests with scope: 'profile'
            → Blocs disposed cleanly, no orphaned callbacks
```

#### 3. Cache That Makes Sense

```dart
// Show cached immediately, refresh in background
GetEvent(
  url: '/api/feed',
  cachePolicy: CachePolicy.staleWhileRevalidate,
  ttl: Duration(minutes: 5),
)

// User sees content instantly, gets fresh data moments later
```

#### 4. Typed Errors You Can Handle

```dart
try {
  await event.result;
} on NetworkError {
  showOfflineMessage();
} on HttpError catch (e) {
  if (e.statusCode == 401) {
    redirectToLogin();
  } else if (e.statusCode == 404) {
    showNotFound();
  }
} on DecodeError {
  reportToSentry();  // Our model is wrong
}
```

#### 5. Observable Everything

```dart
// In your debug drawer / inspector:
class NetworkInspectorWidget extends StatelessJuiceWidget<FetchBloc> {
  NetworkInspectorWidget({super.key})
      : super(groups: {'fetch:inflight', 'fetch:stats'});

  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    final state = bloc.state;
    return Column(children: [
      Text('Inflight: ${state.inflightCount}'),
      Text('Cache hits: ${state.stats.cacheHits}'),
      Text('Cache misses: ${state.stats.cacheMisses}'),
      for (final req in state.activeRequests.values)
        Text('${req.key.method} ${req.key.url} - ${req.phase}'),
    ]);
  }
}
```

### Who Should Use FetchBloc?

| If you... | Use FetchBloc? |
|-----------|----------------|
| Have 1 API call in your app | Probably overkill |
| Have 5+ screens making API calls | **Yes** |
| Need caching | **Yes** |
| Need to show loading states | **Yes** |
| Have auth tokens | **Yes** |
| Want request observability | **Yes** |
| Are building a "real" app | **Yes** |

### Who Shouldn't?

- Single-endpoint utilities (just use Dio directly)
- Apps where you truly don't care about caching, errors, or observability
- Prototypes you'll throw away

---

## Foundation Contract

FetchBloc guarantees these behaviors:

### A. Deterministic Request Identity

Every request has a stable `RequestKey`:

```
RequestKey = method + url + canonicalQuery + bodyHash + authScope + variant
```

This enables reliable deduplication and caching.

### B. Inflight Coalescing

If 5 widgets request the same key simultaneously:
- Only 1 network call executes
- All 5 await the same future / receive the same stream update

### C. Cache Policy

Single enum developers can understand:

| Policy | Behavior |
|--------|----------|
| `networkOnly` | Always fetch, never cache |
| `cacheOnly` | Only return cached, never fetch |
| `cacheFirst` | Return cache if valid, else fetch |
| `networkFirst` | Fetch first, fall back to cache on failure |
| `staleWhileRevalidate` | Return stale immediately, refresh in background |

TTL support plugs into StorageBloc.

### D. Typed Decode

```dart
final user = await fetchBloc.getJson<User>(
  '/users/123',
  decode: User.fromJson,
);
```

Failures are typed, not string error soup.

### E. Cancellation

- Cancel by `RequestKey`
- Cancel by `scope/tag` (e.g., screen disposed)

### F. Interceptors

Simple chain for:
- Auth header injection
- Logging/metrics
- Response normalization
- Backoff/retry policy
- 401 refresh handling

---

## State Model

### FetchState

```dart
@immutable
class FetchState extends BlocState {
  /// Whether the bloc is initialized
  final bool isInitialized;

  /// Current network configuration
  final FetchConfig config;

  /// Number of requests currently in flight
  final int inflightCount;

  /// Map of active requests by key
  final Map<RequestKey, RequestStatus> activeRequests;

  /// Cache statistics
  final CacheStats cacheStats;

  /// Last error that occurred
  final FetchError? lastError;

  /// Optional: bounded map of last responses by key
  final Map<RequestKey, CachedResponse>? lastResponses;

  /// Network statistics
  final NetworkStats stats;
}
```

### NetworkStats

```dart
@immutable
class NetworkStats {
  final int cacheHits;
  final int cacheMisses;
  final int totalRequests;
  final int failedRequests;
  final int retryCount;
  final int bytesReceived;
  final int bytesSent;
  final Duration totalLatency;
}
```

### RequestStatus

```dart
enum RequestPhase {
  pending,
  inflight,
  completed,
  failed,
  cancelled,
}

@immutable
class RequestStatus {
  final RequestKey key;
  final RequestPhase phase;
  final DateTime startedAt;
  final Duration? elapsed;
  final int attemptCount;
  final CancelToken? cancelToken;

  /// Scope for grouped cancellation (e.g., screen name, feature area)
  final String? scope;

  const RequestStatus({
    required this.key,
    required this.phase,
    required this.startedAt,
    this.elapsed,
    this.attemptCount = 1,
    this.cancelToken,
    this.scope,
  });

  factory RequestStatus.inflight(RequestKey key, {String? scope, CancelToken? cancelToken}) {
    return RequestStatus(
      key: key,
      phase: RequestPhase.inflight,
      startedAt: DateTime.now(),
      cancelToken: cancelToken,
      scope: scope,
    );
  }
}
```

### Scope-Based Cancellation

Scope allows cancelling groups of related requests:

```dart
// All requests on this screen share a scope
fetchBloc.send(GetEvent(url: '/api/users', scope: 'user-list-screen'));
fetchBloc.send(GetEvent(url: '/api/roles', scope: 'user-list-screen'));

// On screen dispose, cancel all
fetchBloc.send(CancelRequestEvent(scope: 'user-list-screen'));
```

Scope cancellation cancels all requests where `requestStatus.scope == event.scope`.

---

## Request Key

### Canonical Key Format

```dart
@immutable
class RequestKey {
  final String method;
  final Uri canonicalUrl;
  final String? bodyHash;
  final String? headerVaryHash;  // Hash of identity-affecting headers
  final String? authScope;
  final String? variant;

  const RequestKey._({
    required this.method,
    required this.canonicalUrl,
    this.bodyHash,
    this.headerVaryHash,
    this.authScope,
    this.variant,
  });

  /// Generates canonical string for deduplication and caching
  String get canonical => [
    method,
    canonicalUrl.toString(),
    bodyHash ?? '',
    headerVaryHash ?? '',
    authScope ?? '',
    variant ?? '',
  ].join(':');

  /// Generate from request parameters
  factory RequestKey.from({
    required String method,
    required String url,
    Map<String, dynamic>? queryParams,
    Map<String, String>? headers,
    Object? body,
    String? authScope,
    String? variant,
  }) {
    final canonicalUrl = _canonicalizeUrl(url, queryParams);
    final bodyHash = body != null ? _hashBody(body) : null;
    final headerVaryHash = headers != null ? _hashIdentityHeaders(headers) : null;

    return RequestKey._(
      method: method.toUpperCase(),
      canonicalUrl: canonicalUrl,
      bodyHash: bodyHash,
      headerVaryHash: headerVaryHash,
      authScope: authScope,
      variant: variant,
    );
  }

  /// REQUIRED: Value equality based on canonical string
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RequestKey && canonical == other.canonical;

  @override
  int get hashCode => canonical.hashCode;

  @override
  String toString() => 'RequestKey($canonical)';
}
```

### RequestKey Equality Contract

**CRITICAL:** `RequestKey` MUST implement value equality based on `canonical`.

Without this, `Map<RequestKey, ...>` and `Set<RequestKey>` operations will fail silently:
- Coalescing won't coalesce (each key is unique by identity)
- Cache lookups will miss (same logical key, different instance)

```dart
// This MUST be true:
final key1 = RequestKey.from(method: 'GET', url: '/api?a=1&b=2');
final key2 = RequestKey.from(method: 'GET', url: '/api?b=2&a=1');
assert(key1 == key2);
assert(key1.hashCode == key2.hashCode);
```

### Canonicalization Rules

These rules are **required** for deterministic deduplication and caching across callers.

#### 1. URL Canonicalization

```
scheme://host:port/path?canonicalQuery
```

- Scheme: lowercase (`HTTPS` → `https`)
- Host: lowercase, no trailing dot
- Port: omit if default (80 for http, 443 for https)
- Path: normalize `.` and `..`, preserve trailing slash as-is
- Fragment: **excluded** from key (fragments are client-side only)

#### 2. Query Parameter Canonicalization

**Sort order:** lexicographic by key, then by value for repeated keys.

```dart
// Input: ?z=1&a=2&a=1&b=3
// Canonical: ?a=1&a=2&b=3&z=1
```

**Rules:**
- Keys sorted alphabetically (case-sensitive)
- Repeated keys: preserve all values, sorted alphabetically
- Empty values preserved: `?key=` → `?key=`
- Valueless keys preserved: `?key` → `?key`
- URL-encode consistently (uppercase hex: `%2F` not `%2f`)

#### 3. Body Hashing

For POST/PUT/PATCH requests, body contributes to identity via SHA-256 hash.

| Body Type | Canonicalization |
|-----------|------------------|
| **JSON** | Canonical JSON: sorted keys, no whitespace, UTF-8, then SHA-256 |
| **Form data** | Sorted key=value pairs, `&`-joined, URL-encoded, then SHA-256 |
| **Multipart** | Sorted parts by name, each part's content hashed, combined |
| **Binary/Stream** | Direct SHA-256 of bytes |
| **null/empty** | No bodyHash in key |

**Canonical JSON example:**
```dart
// Input: {"b": 1, "a": {"d": 2, "c": 3}}
// Canonical: {"a":{"c":3,"d":2},"b":1}
// Hash: SHA256 of that UTF-8 string
```

#### 4. Headers in Identity

**Only these headers contribute to identity** (prevents keyspace explosion):

| Header | When Included |
|--------|---------------|
| `Accept` | Always (affects response format) |
| `Content-Type` | When body present |
| `X-Api-Version` | If present (affects response shape) |
| `Accept-Language` | If present (affects content) |

**NOT included:** `User-Agent`, `Cookie`, `Cache-Control`, `Authorization` (use `authScope`), timestamps, request IDs.

**Computing `headerVaryHash`:**

```dart
String? _hashIdentityHeaders(Map<String, String> headers) {
  const identityHeaders = ['accept', 'content-type', 'x-api-version', 'accept-language'];

  final normalized = <String>[];
  for (final name in identityHeaders) {
    final value = headers[name] ?? headers[name.toLowerCase()];
    if (value != null && value.isNotEmpty) {
      normalized.add('${name.toLowerCase()}=${value.trim().toLowerCase()}');
    }
  }

  if (normalized.isEmpty) return null;

  normalized.sort();
  return sha256.convert(utf8.encode(normalized.join('&'))).toString().substring(0, 16);
}
```

**Authorization is handled separately via `authScope`** (not in header hash):

```dart
// Bearer token → authScope: "bearer:user123"
// API key → authScope: "apikey:project456"
// None → authScope: null
```

This separates auth identity from auth credentials — the token value doesn't affect the key, only the scope/user identity does.

#### 5. Variant / Namespace

Optional escape hatch for "same URL, different meaning":

```dart
// Same endpoint, different tenants
RequestKey.from(url: '/api/users', variant: 'tenant:acme');
RequestKey.from(url: '/api/users', variant: 'tenant:globex');
```

Use sparingly. If you need it often, your URL structure may need work.

---

## Coalescing Semantics

### Raw-Response Coalescing (Required Behavior)

Coalescing happens at the **wire level**, not the typed level:

```
┌──────────────────────────────────────────────────────────┐
│  5 callers request same RequestKey                       │
│    ↓                                                     │
│  1 network request fires                                 │
│    ↓                                                     │
│  Raw response bytes cached                               │
│    ↓                                                     │
│  Each caller decodes independently (or shares if same T) │
└──────────────────────────────────────────────────────────┘
```

**Why this matters:**
- If `T` were part of the key, `getJson<User>` and `getJson<Map>` for the same URL would make 2 requests
- Decode errors don't poison the cache (raw bytes are fine, decoder had a bug)
- Same response can be decoded to different types by different callers

### Coalescing Implementation

**Authority model:**
- `RequestCoalescer._inflight` is **authoritative** for coalescing behavior
- `FetchState.activeRequests` is **observability** (derived, for UI/debugging)

The coalescer owns the inflight tracking; state mirrors it for widget rebuilds.

```dart
class RequestCoalescer {
  final Map<String, _InflightEntry> _inflight = {};

  /// Callback to notify state when inflight changes
  final void Function(String canonical, bool isInflight)? onInflightChanged;

  Future<Response> coalesce(
    RequestKey key,
    Future<Response> Function() execute,
  ) async {
    final canonical = key.canonical;

    if (_inflight.containsKey(canonical)) {
      // Join existing request - DO NOT fire another network call
      return _inflight[canonical]!.future;
    }

    // First caller - execute and share
    final completer = Completer<Response>();
    _inflight[canonical] = _InflightEntry(completer.future, key);
    onInflightChanged?.call(canonical, true);  // Notify state

    try {
      final response = await execute();
      completer.complete(response);
      return response;
    } catch (e) {
      completer.completeError(e);
      rethrow;
    } finally {
      _inflight.remove(canonical);
      onInflightChanged?.call(canonical, false);  // Notify state
    }
  }

  /// Get current inflight keys (for state sync)
  Set<String> get inflightKeys => _inflight.keys.toSet();
}

class _InflightEntry {
  final Future<Response> future;
  final RequestKey key;
  _InflightEntry(this.future, this.key);
}
```

### State Synchronization

`FetchState.activeRequests` is updated via coalescer callbacks:

```dart
// In FetchBloc initialization
_coalescer = RequestCoalescer(
  onInflightChanged: (canonical, isInflight) {
    if (isInflight) {
      emit(state.copyWith(
        activeRequests: {...state.activeRequests, canonical: RequestStatus.inflight(...)},
        inflightCount: state.inflightCount + 1,
      ));
    } else {
      emit(state.copyWith(
        activeRequests: {...state.activeRequests}..remove(canonical),
        inflightCount: state.inflightCount - 1,
      ));
    }
  },
);
```

### Decode Isolation

```dart
// In ExecuteRequestUseCase
final response = await _coalescer.coalesce(key, () => _dio.request(...));

// Cache raw bytes BEFORE decoding
if (event.cachePolicy.shouldCache && !_isSensitive(key, response)) {
  await _cacheManager.put(key, WireCacheRecord.fromResponse(response));
}

// Decode happens AFTER coalescing, per-caller
try {
  final jsonData = jsonDecode(utf8.decode(response.bodyBytes));
  final decoded = event.decode?.call(jsonData) ?? jsonData;
  return decoded;
} catch (e) {
  // Decode error - doesn't affect other callers or cache
  throw DecodeError(expectedType: T, actualValue: response.data, cause: e);
}
```

### Stale-While-Revalidate Refresh

Background refresh must coalesce but bypass cache read:

```dart
void _refreshInBackground(RequestKey key, RequestEvent event) {
  // Use same coalescer - if another refresh is in flight, join it
  _coalescer.coalesce(key, () => _executeNetwork(event, revalidate: true))
    .then((response) {
      // Update cache with fresh data
      _cacheManager.put(key, WireCacheRecord.fromResponse(response));
      // Emit to trigger rebuilds
      emit(state, groupsToRebuild: ['fetch:request:${key.canonical}']);
    })
    .catchError((_) {
      // Background refresh failure is silent - stale data still served
    });
}
```

---

## Cache Policy

### CachePolicy Enum

```dart
enum CachePolicy {
  /// Always fetch from network, never use cache
  networkOnly,

  /// Only return cached data, never fetch
  cacheOnly,

  /// Return cache if valid, otherwise fetch
  cacheFirst,

  /// Always fetch, fall back to cache on failure
  networkFirst,

  /// Return stale cache immediately, refresh in background
  staleWhileRevalidate,
}
```

### Cache Storage Model

**CRITICAL:** Cache stores **raw wire response**, not decoded types.

This prevents:
- Decoder bugs from corrupting cache
- Type `T` from fragmenting cache (same URL, different decoders = same cache entry)
- Serialization issues with complex types

#### WireCacheRecord (what gets persisted)

```dart
@immutable
class WireCacheRecord {
  /// The request key this caches
  final String canonicalKey;

  /// Raw response body bytes
  final Uint8List bodyBytes;

  /// HTTP status code
  final int statusCode;

  /// Response headers (subset: content-type, etag, last-modified, cache-control)
  final Map<String, String> headers;

  /// When this was cached
  final DateTime cachedAt;

  /// When this expires (computed from TTL or Cache-Control)
  final DateTime? expiresAt;

  /// ETag for conditional requests
  final String? etag;

  /// Last-Modified for conditional requests
  final String? lastModified;

  /// Size for cache eviction
  int get sizeBytes => bodyBytes.length;

  /// Check if expired
  bool get isExpired => expiresAt != null && DateTime.now().isAfter(expiresAt!);

  /// Check if stale (expired but still usable for stale-while-revalidate)
  bool get isStale => isExpired;
}
```

#### Decode happens per-caller, AFTER cache retrieval

```dart
// In use case:
final wireRecord = await _cacheManager.get(key);
if (wireRecord != null && !wireRecord.isExpired) {
  // Decode from raw bytes - each caller decodes independently
  final jsonData = jsonDecode(utf8.decode(wireRecord.bodyBytes));
  return event.decode?.call(jsonData) ?? jsonData;
}
```

#### Optional: Decoded cache (explicit opt-in, best-effort)

For performance-critical paths, allow caching decoded values in memory (not persisted):

```dart
GetEvent(
  url: '/api/user',
  decode: User.fromJson,
  cacheDecodedInMemory: true,  // In-memory only, not persisted
);
```

This is optimization, not correctness - the wire cache remains authoritative.

### TTL Integration

Cache entries are stored via StorageBloc with TTL metadata:
```dart
storageBloc.send(HiveWriteEvent(
  box: '_fetch_cache',
  key: requestKey.canonical,
  value: wireCacheRecord.toBytes(),  // Raw bytes, not decoded
  ttl: policy.ttl,
));
```

### Cache Eviction Strategy

When cache exceeds `maxCacheSize`:

1. **Eviction trigger:** On every cache write
2. **Eviction order:** LRU by `cachedAt` (oldest first)
3. **Eviction target:** Remove entries until under 90% of `maxCacheSize`
4. **Size computation:** `WireCacheRecord.sizeBytes` (body bytes length)

```dart
Future<void> _evictIfNeeded() async {
  final currentSize = await _computeTotalSize();
  if (currentSize <= config.maxCacheSize) return;

  final target = (config.maxCacheSize * 0.9).toInt();
  final entries = await _getAllEntriesSortedByAge();

  var freedBytes = 0;
  for (final entry in entries) {
    if (currentSize - freedBytes <= target) break;
    await _deleteEntry(entry.key);
    freedBytes += entry.sizeBytes;
  }
}
```

### Cache Safety Rules

Default behaviors that prevent accidental sensitive data caching:

#### 1. Authorization-Protected Responses

```dart
// Default: DO NOT cache responses when request has Authorization header
// Unless explicitly opted in:
GetEvent(
  url: '/api/profile',
  cachePolicy: CachePolicy.cacheFirst,
  cacheAuthResponses: true,  // Explicit opt-in required
);
```

#### 2. Sensitive Endpoints

Never cache by default (even with `cacheAuthResponses: true`):
- Endpoints matching `/auth/*`, `/login`, `/token`, `/oauth/*`
- Responses containing `Set-Cookie` header
- Responses with `Cache-Control: no-store`

Override only with `forceCache: true` (not recommended).

#### 3. Cache-Control Respect

| Server Header | FetchBloc Behavior |
|---------------|-------------------|
| `Cache-Control: no-store` | Never cache (unless `forceCache`) |
| `Cache-Control: no-cache` | Cache but always revalidate |
| `Cache-Control: max-age=N` | Use as TTL if no explicit TTL set |
| `Cache-Control: private` | Cache only if single-user context |
| `Vary: *` | Do not cache |

#### 4. ETag / Conditional Requests

When cached entry has ETag or Last-Modified:

```dart
// Outgoing request adds:
If-None-Match: "abc123"
If-Modified-Since: Wed, 21 Oct 2024 07:28:00 GMT

// On 304 Not Modified:
// - Return cached body
// - Update cache timestamp
// - Increment cache hit stats
```

#### 5. Vary Header Handling

Simplified approach (full Vary is complex):

```dart
// If response has Vary header, include varied header values in cache key
// Example: Vary: Accept-Language
// Cache key becomes: GET:/api/content:...:accept-language=en-US
```

Only support common Vary values: `Accept`, `Accept-Language`, `Accept-Encoding`.
Log warning for unsupported Vary values.

---

## Retry & Refresh Correctness

### Retry Safety Rules

**Critical:** Auto-retry only when safe.

| Method | Default Retryable | Reason |
|--------|-------------------|--------|
| GET | Yes | Idempotent read |
| HEAD | Yes | Idempotent read |
| PUT | Yes | Idempotent write (replace) |
| DELETE | Yes | Idempotent (delete twice = same result) |
| POST | **No** | Non-idempotent (may create duplicates) |
| PATCH | **No** | Non-idempotent (depends on current state) |

To retry POST/PATCH, require explicit opt-in:

```dart
PostEvent(
  url: '/api/orders',
  body: order,
  retryable: true,           // Explicit opt-in
  idempotencyKey: 'order-123', // Required for retryable POST
);
```

### Retry Conditions

Only retry on:
- Network errors (no response received)
- Timeout errors
- 5xx server errors (except 501 Not Implemented)
- 429 Too Many Requests (with backoff from Retry-After)

Never retry on:
- 4xx client errors (except 429)
- Successful responses
- Request cancellation

### Token Refresh Singleflight

**Requirement:** Only one refresh in flight; others await it.

```dart
class RefreshTokenInterceptor {
  Completer<String>? _refreshInFlight;

  Future<String?> ensureValidToken() async {
    if (_refreshInFlight != null) {
      // Another request already refreshing - wait for it
      return _refreshInFlight!.future;
    }

    if (!_isTokenExpired()) {
      return _currentToken;
    }

    // Start refresh - others will await this
    _refreshInFlight = Completer<String>();

    try {
      final newToken = await _refreshToken();
      _refreshInFlight!.complete(newToken);
      return newToken;
    } catch (e) {
      _refreshInFlight!.completeError(e);
      rethrow;
    } finally {
      _refreshInFlight = null;
    }
  }
}
```

This prevents "401 storm" where N concurrent requests all trigger N refresh attempts.

### Retry Backoff Strategy

Default: exponential backoff with jitter.

```dart
Duration backoff(int attempt) {
  final base = Duration(milliseconds: 500);
  final maxDelay = Duration(seconds: 30);
  final exponential = base * pow(2, attempt - 1);
  final jitter = Random().nextDouble() * 0.3; // ±15%
  final withJitter = exponential * (1 + jitter - 0.15);
  return withJitter.clamp(base, maxDelay);
}

// Attempt 1: ~500ms
// Attempt 2: ~1s
// Attempt 3: ~2s
// Attempt 4: ~4s (capped at 30s)
```

---

## Events Contract

This is the **stable, contractual event surface** for FetchBloc v0.1.0.

### Event Input/Output Contract

#### Request Events (return typed data)

| Event | Key Inputs | Output | Errors |
|-------|------------|--------|--------|
| `GetEvent<T>` | `url`, `queryParams?`, `headers?`, `decode?` | `Future<T>` via `event.result` | `NetworkError`, `HttpError`, `DecodeError`, `CancelledError` |
| `PostEvent<T>` | `url`, `body?`, `decode?` | `Future<T>` via `event.result` | Same |
| `PutEvent<T>` | `url`, `body?`, `decode?` | `Future<T>` via `event.result` | Same |
| `PatchEvent<T>` | `url`, `body?`, `decode?` | `Future<T>` via `event.result` | Same |
| `DeleteEvent<T>` | `url`, `decode?` | `Future<T>` via `event.result` | Same |

**Usage pattern:**
```dart
final event = GetEvent<User>(
  url: '/api/users/123',
  decode: User.fromJson,
  cachePolicy: CachePolicy.cacheFirst,
);
fetchBloc.send(event);
final user = await event.result;  // User or throws FetchError
```

#### Lifecycle Events (no return value)

| Event | Key Inputs | Effect | State Change |
|-------|------------|--------|--------------|
| `InitializeFetchEvent` | `config?`, `platformConfig?`, `interceptors?` | Configures Dio + interceptors | `isInitialized = true` |
| `ResetFetchEvent` | `clearCache?`, `cancelInflight?`, `resetStats?` | Returns to baseline | Per flags |

**Usage pattern:**
```dart
fetchBloc.send(InitializeFetchEvent(
  config: FetchConfig(baseUrl: 'https://api.example.com'),
));
// No await needed - state updates trigger widget rebuilds via groups
```

#### Cache Events (no return value)

| Event | Key Inputs | Effect | State Change |
|-------|------------|--------|--------------|
| `InvalidateCacheEvent` | `key?`, `urlPattern?`, `namespace?` | Removes matching entries | `cacheStats` updated |
| `ClearCacheEvent` | `namespace?` | Clears all/namespace | `cacheStats` updated |
| `PruneCacheEvent` | `targetBytes?` | LRU eviction to size | `cacheStats` updated |
| `CleanupExpiredCacheEvent` | `namespace?` | Removes TTL-expired | `cacheStats` updated |

**Usage pattern:**
```dart
// Invalidate specific key
fetchBloc.send(InvalidateCacheEvent(key: userRequestKey));

// Clear all user-related cache
fetchBloc.send(ClearCacheEvent(namespace: 'user'));

// Force size limit enforcement
fetchBloc.send(PruneCacheEvent(targetBytes: 10 * 1024 * 1024));
```

#### Cancellation Events (no return value)

| Event | Key Inputs | Effect | Caller Impact |
|-------|------------|--------|---------------|
| `CancelRequestEvent` | `key` (required) | Cancels one request | `event.result` throws `CancelledError` |
| `CancelScopeEvent` | `scope` (required) | Cancels all in scope | All matching throw `CancelledError` |
| `CancelAllEvent` | `reason?` | Cancels everything | All inflight throw `CancelledError` |

**Usage pattern:**
```dart
// In screen dispose
@override
void dispose() {
  fetchBloc.send(CancelScopeEvent(scope: 'user-profile-screen'));
  super.dispose();
}
```

#### Observability Events (no return value)

| Event | Key Inputs | Effect | State Change |
|-------|------------|--------|--------------|
| `ResetStatsEvent` | none | Zeros counters | `stats` reset |
| `ClearLastErrorEvent` | none | Clears error | `lastError = null` |

### Event Summary

| Category | Event | Status | ResultEvent |
|----------|-------|--------|-------------|
| **Lifecycle** | `InitializeFetchEvent` | Required | No |
| | `ResetFetchEvent` | Optional | No |
| **Requests** | `GetEvent<T>` | Required | Yes |
| | `PostEvent<T>` | Required | Yes |
| | `PutEvent<T>` | Required | Yes |
| | `PatchEvent<T>` | Required | Yes |
| | `DeleteEvent<T>` | Required | Yes |
| | `HeadEvent<T>` | Optional | Yes |
| **Cache** | `InvalidateCacheEvent` | Required | No |
| | `ClearCacheEvent` | Required | No |
| | `PruneCacheEvent` | Required | No |
| | `CleanupExpiredCacheEvent` | Recommended | No |
| **Cancellation** | `CancelRequestEvent` | Required | No |
| | `CancelScopeEvent` | Required | No |
| | `CancelAllEvent` | Required | No |
| **Observability** | `ResetStatsEvent` | Recommended | No |
| | `ClearLastErrorEvent` | Recommended | No |

### Event Base Contract

All events extend `FetchEvent`:

```dart
abstract class FetchEvent extends EventBase {
  /// Groups to rebuild when this event completes
  final Set<String>? groupsToRebuild;

  /// Scope for grouping (cancellation, logging)
  final String? scope;

  /// Debug label for inspector/logging
  final String? debugLabel;

  const FetchEvent({
    this.groupsToRebuild,
    this.scope,
    this.debugLabel,
  });
}
```

Events producing a result extend juice core's `ResultEvent<T>`:

```dart
/// From juice core - FetchBloc events extend this
abstract class ResultEvent<TResult> extends EventBase {
  final Completer<TResult> _completer = Completer<TResult>();

  /// Future that completes with the result or error
  Future<TResult> get result => _completer.future;

  /// Whether this event's result has been completed.
  bool get isCompleted => _completer.isCompleted;

  /// Complete the result successfully with [value].
  void succeed(TResult value);

  /// Complete the result with an error.
  void fail(Object error, [StackTrace? stackTrace]);
}
```

FetchBloc request events extend `ResultEvent<T>` from juice core, ensuring consistent result handling across the ecosystem.

---

### 1. Lifecycle Events

#### `InitializeFetchEvent` ✅ Required

```dart
class InitializeFetchEvent extends FetchEvent {
  /// Platform-neutral configuration
  final FetchConfig config;

  /// Platform-specific configuration
  final PlatformConfig? platformConfig;

  /// Custom interceptors (sorted by priority)
  final List<FetchInterceptor>? interceptors;

  const InitializeFetchEvent({
    this.config = const FetchConfig(),
    this.platformConfig,
    this.interceptors,
    super.debugLabel,
  });
}
```

**Semantics:**
- Idempotent: calling twice does not break anything
- Emits state where `isInitialized == true`
- Interceptor chain installed in priority order

**Groups emitted:** `fetch:config`

#### `ResetFetchEvent` ⚠️ Optional

```dart
class ResetFetchEvent extends FetchEvent {
  final bool clearCache;
  final bool cancelInflight;
  final bool resetStats;

  const ResetFetchEvent({
    this.clearCache = false,
    this.cancelInflight = true,
    this.resetStats = true,
    super.debugLabel,
  });
}
```

**Semantics:** Return to known baseline (useful for demos/tests).

---

### 2. Request Events

#### `RequestEvent<T>` Base ✅ Required

```dart
abstract class RequestEvent<T> extends ResultEvent<T> implements FetchEvent {
  // === Identity / Routing ===
  final String url;
  final Map<String, dynamic>? queryParams;
  final Map<String, String>? headers;
  final String? variant;
  final RequestKey? keyOverride;

  // === Cache Policy ===
  final CachePolicy cachePolicy;
  final Duration? ttl;
  final bool cacheAuthResponses;      // Default: false
  final bool forceCache;              // Default: false
  final bool cacheDecodedInMemory;    // Default: false
  final bool allowStaleOnError;       // Default: true (for networkFirst)

  // === Retry Policy ===
  final bool retryable;               // Default: per method
  final int? maxAttempts;             // Override default
  final String? idempotencyKey;       // REQUIRED if retryable POST/PATCH

  // === Decode ===
  final T Function(dynamic raw)? decode;
  final bool returnRaw;               // Default: false

  // === Common ===
  final String? scope;
  final Set<String>? groupsToRebuild;
}
```

#### Concrete Request Events

```dart
class GetEvent<T> extends RequestEvent<T> {
  const GetEvent({
    required super.url,
    super.queryParams,
    super.headers,
    super.cachePolicy = CachePolicy.networkFirst,
    super.ttl,
    super.cacheAuthResponses = false,
    super.forceCache = false,
    super.allowStaleOnError = true,
    super.retryable = true,           // GET is idempotent
    super.maxAttempts,
    super.idempotencyKey,
    super.decode,
    super.returnRaw = false,
    super.scope,
    super.variant,
    super.keyOverride,
    super.groupsToRebuild,
    super.debugLabel,
  });
}

class PostEvent<T> extends RequestEvent<T> {
  final Object? body;

  const PostEvent({
    required super.url,
    this.body,
    super.queryParams,
    super.headers,
    super.cachePolicy = CachePolicy.networkOnly,
    super.ttl,
    super.cacheAuthResponses = false,
    super.forceCache = false,
    super.allowStaleOnError = false,
    super.retryable = false,          // POST is NOT idempotent
    super.maxAttempts,
    super.idempotencyKey,             // REQUIRED if retryable = true
    super.decode,
    super.returnRaw = false,
    super.scope,
    super.variant,
    super.keyOverride,
    super.groupsToRebuild,
    super.debugLabel,
  });
}

class PutEvent<T> extends RequestEvent<T> {
  final Object? body;

  const PutEvent({
    required super.url,
    this.body,
    super.queryParams,
    super.headers,
    super.cachePolicy = CachePolicy.networkOnly,
    super.ttl,
    super.cacheAuthResponses = false,
    super.forceCache = false,
    super.allowStaleOnError = false,
    super.retryable = true,           // PUT is idempotent (replace)
    super.maxAttempts,
    super.idempotencyKey,
    super.decode,
    super.returnRaw = false,
    super.scope,
    super.variant,
    super.keyOverride,
    super.groupsToRebuild,
    super.debugLabel,
  });
}

class PatchEvent<T> extends RequestEvent<T> {
  final Object? body;

  const PatchEvent({
    required super.url,
    this.body,
    super.queryParams,
    super.headers,
    super.cachePolicy = CachePolicy.networkOnly,
    super.ttl,
    super.cacheAuthResponses = false,
    super.forceCache = false,
    super.allowStaleOnError = false,
    super.retryable = false,          // PATCH is NOT idempotent
    super.maxAttempts,
    super.idempotencyKey,             // REQUIRED if retryable = true
    super.decode,
    super.returnRaw = false,
    super.scope,
    super.variant,
    super.keyOverride,
    super.groupsToRebuild,
    super.debugLabel,
  });
}

class DeleteEvent<T> extends RequestEvent<T> {
  const DeleteEvent({
    required super.url,
    super.queryParams,
    super.headers,
    super.cachePolicy = CachePolicy.networkOnly,
    super.ttl,
    super.cacheAuthResponses = false,
    super.forceCache = false,
    super.allowStaleOnError = false,
    super.retryable = true,           // DELETE is idempotent
    super.maxAttempts,
    super.idempotencyKey,
    super.decode,
    super.returnRaw = false,
    super.scope,
    super.variant,
    super.keyOverride,
    super.groupsToRebuild,
    super.debugLabel,
  });
}

// Optional
class HeadEvent<T> extends RequestEvent<T> {
  const HeadEvent({
    required super.url,
    super.queryParams,
    super.headers,
    super.cachePolicy = CachePolicy.networkOnly,
    super.retryable = true,
    super.scope,
    super.debugLabel,
  });
}
```

**Groups emitted:** `fetch:request:{canonical}`, `fetch:inflight`

#### Event Validation

```dart
void _validateEvent(RequestEvent event) {
  if (event.retryable &&
      (event is PostEvent || event is PatchEvent) &&
      event.idempotencyKey == null) {
    throw ArgumentError(
      'Retryable POST/PATCH requires idempotencyKey.',
    );
  }
}
```

---

### 3. Cache Management Events

#### `InvalidateCacheEvent` ✅ Required

```dart
class InvalidateCacheEvent extends FetchEvent {
  /// Specific key to invalidate
  final RequestKey? key;

  /// URL pattern (glob) to match
  final String? urlPattern;

  /// Namespace to scope invalidation
  final String? namespace;

  /// Include already-expired entries
  final bool includeExpired;

  const InvalidateCacheEvent({
    this.key,
    this.urlPattern,
    this.namespace,
    this.includeExpired = true,
    super.debugLabel,
  });
}
```

**Groups emitted:** `fetch:cache`

#### `ClearCacheEvent` ✅ Required

```dart
class ClearCacheEvent extends FetchEvent {
  /// Namespace to clear (null = all)
  final String? namespace;

  const ClearCacheEvent({
    this.namespace,
    super.debugLabel,
  });
}
```

**Groups emitted:** `fetch:cache`

#### `PruneCacheEvent` ✅ Required

```dart
class PruneCacheEvent extends FetchEvent {
  /// Target size in bytes (null = use config.maxCacheSize)
  final int? targetBytes;

  /// Remove expired entries first before LRU
  final bool removeExpiredFirst;

  const PruneCacheEvent({
    this.targetBytes,
    this.removeExpiredFirst = true,
    super.debugLabel,
  });
}
```

**Semantics:** Enforces `maxCacheSize` via LRU eviction.

**Groups emitted:** `fetch:cache`

#### `CleanupExpiredCacheEvent` ✅ Recommended

```dart
class CleanupExpiredCacheEvent extends FetchEvent {
  final String? namespace;

  const CleanupExpiredCacheEvent({
    this.namespace,
    super.debugLabel,
  });
}
```

**Semantics:** Deletes TTL-expired entries.

**Groups emitted:** `fetch:cache`

---

### 4. Cancellation Events

#### `CancelRequestEvent` ✅ Required

```dart
class CancelRequestEvent extends FetchEvent {
  /// Key of request to cancel
  final RequestKey key;

  /// Reason for cancellation (for logging)
  final String? reason;

  const CancelRequestEvent({
    required this.key,
    this.reason,
    super.debugLabel,
  });
}
```

**Semantics:**
- Cancels underlying in-flight work
- Completes waiting callers with `CancelledError`
- Removes from `activeRequests`, decrements inflight count

**Groups emitted:** `fetch:request:{canonical}`, `fetch:inflight`

#### `CancelScopeEvent` ✅ Required

```dart
class CancelScopeEvent extends FetchEvent {
  /// Scope to cancel
  final String scope;

  /// Reason for cancellation
  final String? reason;

  const CancelScopeEvent({
    required this.scope,
    this.reason,
    super.debugLabel,
  });
}
```

**Semantics:** Cancels all requests where `requestStatus.scope == scope`.

**Groups emitted:** `fetch:inflight` (plus per-request groups)

#### `CancelAllEvent` ✅ Required

```dart
class CancelAllEvent extends FetchEvent {
  final String? reason;

  const CancelAllEvent({
    this.reason,
    super.debugLabel,
  });
}
```

**Semantics:** Cancels all inflight requests.

**Groups emitted:** `fetch:inflight`

---

### 5. Observability Events

#### `ResetStatsEvent` ✅ Recommended

```dart
class ResetStatsEvent extends FetchEvent {
  const ResetStatsEvent({super.debugLabel});
}
```

**Semantics:** Zeros out `NetworkStats`.

**Groups emitted:** `fetch:stats`

#### `ClearLastErrorEvent` ✅ Recommended

```dart
class ClearLastErrorEvent extends FetchEvent {
  const ClearLastErrorEvent({super.debugLabel});
}
```

**Semantics:** Clears `state.lastError` without affecting cache/inflight.

**Groups emitted:** `fetch:error`

---

### 6. Deferred Events (Not in v0.1.0)

These are **explicitly not contractual** for v0.1.0:

| Event | Reason |
|-------|--------|
| `PauseRequestsEvent` | Requires offline queue semantics |
| `ResumeRequestsEvent` | Requires offline queue semantics |
| `EnqueueOutboxEvent` | Deferred to v0.2+ |
| `FlushOutboxEvent` | Deferred to v0.2+ |
| `SetInterceptorsEvent` | Runtime mutation adds complexity |

---

### Event → Groups Emitted Mapping

| Event | Groups Emitted |
|-------|----------------|
| `InitializeFetchEvent` | `fetch:config` |
| `ResetFetchEvent` | `fetch:config`, `fetch:cache`, `fetch:stats`, `fetch:inflight` |
| `GetEvent` / `PostEvent` / etc. | `fetch:request:{canonical}`, `fetch:inflight` |
| `InvalidateCacheEvent` | `fetch:cache` |
| `ClearCacheEvent` | `fetch:cache` |
| `PruneCacheEvent` | `fetch:cache` |
| `CleanupExpiredCacheEvent` | `fetch:cache` |
| `CancelRequestEvent` | `fetch:request:{canonical}`, `fetch:inflight` |
| `CancelScopeEvent` | `fetch:inflight`, `fetch:request:{canonical}` per request |
| `CancelAllEvent` | `fetch:inflight` |
| `ResetStatsEvent` | `fetch:stats` |
| `ClearLastErrorEvent` | `fetch:error` |

---

### Implicit Contracts (All Request Events Must Honor)

1. **Request Identity:** Compute `RequestKey` deterministically via canonicalization rules
2. **Coalescing:** Dedupe inflight by `RequestKey.canonical` (wire-level)
3. **Cache Safety:** Apply defaults (no auth caching, respect no-store)
4. **Typed Errors:** Failures are `FetchError` subtypes, never raw Dio errors
5. **Cancellation:** Cancel stops request, completes with `CancelledError`, cleans state
6. **Groups:** Emit appropriate rebuild groups on phase changes

---

## Use Cases

### Use Case → Widget Rebuild Flow

All use cases trigger widget rebuilds via `emitUpdate()` with `groupsToRebuild`:

```
┌─────────────────────────────────────────────────────────────────┐
│  Use Case                                                        │
│       ↓                                                         │
│  emitUpdate(                                                    │
│    groupsToRebuild: {'fetch:inflight', 'fetch:request:xyz'},    │
│    newState: state.copyWith(...),                               │
│  )                                                              │
│       ↓                                                         │
│  All StatelessJuiceWidgets with matching groups rebuild         │
└─────────────────────────────────────────────────────────────────┘
```

### InitializeFetchUseCase

```dart
class InitializeFetchUseCase extends BlocUseCase<FetchBloc, InitializeFetchEvent> {
  @override
  Future<void> execute(InitializeFetchEvent event) async {
    final dio = Dio(BaseOptions(
      connectTimeout: event.config.connectTimeout,
      receiveTimeout: event.config.receiveTimeout,
    ));

    // Register interceptors
    for (final interceptor in event.interceptors ?? []) {
      dio.interceptors.add(interceptor);
    }

    // Emit with group - all widgets listening to 'fetch:config' will rebuild
    emitUpdate(
      groupsToRebuild: {'fetch:config'},
      newState: bloc.state.copyWith(
        isInitialized: true,
        config: event.config,
      ),
    );
  }
}
```

### ExecuteRequestUseCase

```dart
class ExecuteRequestUseCase extends BlocUseCase<FetchBloc, RequestEvent> {
  @override
  Future<void> execute(RequestEvent event) async {
    final key = event.keyOverride ?? RequestKey.from(...);

    // Check for inflight coalescing
    if (bloc.state.activeRequests.containsKey(key)) {
      return _awaitExisting(key);
    }

    // Check cache based on policy
    if (event.cachePolicy.shouldCheckCache) {
      final cached = await _getFromCache(key);
      if (cached != null && !cached.isExpired) {
        if (event.cachePolicy == CachePolicy.staleWhileRevalidate) {
          _refreshInBackground(key, event);
        }
        return cached.data;
      }
    }

    // Mark as inflight - widgets with 'fetch:inflight' group rebuild
    emitUpdate(
      groupsToRebuild: {'fetch:inflight', 'fetch:request:${key.canonical}'},
      newState: bloc.state.copyWith(
        activeRequests: {...bloc.state.activeRequests, key: RequestStatus.inflight(key)},
        inflightCount: bloc.state.inflightCount + 1,
      ),
    );

    try {
      final response = await _executeWithInterceptors(event);
      final decoded = event.decode?.call(response.data) ?? response.data;

      // Cache if appropriate
      if (event.cachePolicy.shouldCache) {
        await _saveToCache(key, decoded, event.ttl);
      }

      // Complete - widgets with matching groups rebuild
      emitUpdate(
        groupsToRebuild: {'fetch:inflight', 'fetch:request:${key.canonical}'},
        newState: bloc.state.copyWith(
          activeRequests: {...bloc.state.activeRequests}..remove(key),
          inflightCount: bloc.state.inflightCount - 1,
          stats: bloc.state.stats.withSuccess(response.contentLength),
        ),
      );

      return decoded;
    } catch (e) {
      // Emit error state - widgets with 'fetch:error' group rebuild
      emitUpdate(
        groupsToRebuild: {'fetch:inflight', 'fetch:error', 'fetch:request:${key.canonical}'},
        newState: bloc.state.copyWith(
          activeRequests: {...bloc.state.activeRequests}..remove(key),
          inflightCount: bloc.state.inflightCount - 1,
          lastError: FetchError.from(e, key),
        ),
      );

      // Handle failure, potentially fall back to cache
      if (event.cachePolicy == CachePolicy.networkFirst) {
        final stale = await _getFromCache(key, allowExpired: true);
        if (stale != null) return stale.data;
      }
      rethrow;
    }
  }
}
```

### CancelRequestUseCase

```dart
class CancelRequestUseCase extends BlocUseCase<FetchBloc, CancelRequestEvent> {
  @override
  Future<void> execute(CancelRequestEvent event) async {
    final keysToCancel = <RequestKey>[];

    if (event.key != null) {
      bloc.state.activeRequests[event.key]?.cancelToken?.cancel();
      keysToCancel.add(event.key!);
    } else if (event.scope != null) {
      for (final entry in bloc.state.activeRequests.entries) {
        if (entry.value.scope == event.scope) {
          entry.value.cancelToken?.cancel();
          keysToCancel.add(entry.key);
        }
      }
    }

    // Emit with groups for all cancelled requests
    final groups = <String>{'fetch:inflight'};
    for (final key in keysToCancel) {
      groups.add('fetch:request:${key.canonical}');
    }

    emitUpdate(
      groupsToRebuild: groups,
      newState: bloc.state.copyWith(
        activeRequests: {...bloc.state.activeRequests}..removeAll(keysToCancel),
        inflightCount: bloc.state.inflightCount - keysToCancel.length,
      ),
    );
  }
}
```

---

## Interceptor Contract

### Execution Model

Interceptors run in a **pipeline** around the network call:

```
┌─────────────────────────────────────────────────────────────────┐
│  Event received                                                  │
│       ↓                                                         │
│  Cache lookup (if cachePolicy allows)                           │
│       ↓ (cache miss)                                            │
│  Coalescer check (join existing or start new)                   │
│       ↓ (new request)                                           │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  INTERCEPTOR PIPELINE                                    │   │
│  │                                                          │   │
│  │  onRequest chain (sorted by priority, lowest first)      │   │
│  │       ↓                                                  │   │
│  │  Network call (Dio)                                      │   │
│  │       ↓                                                  │   │
│  │  onResponse chain (reverse order) OR onError chain       │   │
│  └─────────────────────────────────────────────────────────┘   │
│       ↓                                                         │
│  Cache write (if policy allows)                                 │
│       ↓                                                         │
│  Decode & return                                                │
└─────────────────────────────────────────────────────────────────┘
```

**Key points:**
- Interceptors run **after** cache lookup and coalescer check
- They only execute for **actual network calls**, not cache hits
- `onRequest` runs in priority order (lowest first)
- `onResponse`/`onError` run in **reverse** order (highest priority last)

### FetchInterceptor

```dart
abstract class FetchInterceptor {
  /// Called before request is sent.
  /// Return modified options, or throw to abort.
  Future<RequestOptions> onRequest(RequestOptions options);

  /// Called after successful response.
  /// Return modified response, or throw to convert to error.
  Future<Response> onResponse(Response response);

  /// Called on error.
  /// Return modified error, throw different error, or return Response to recover.
  Future<dynamic> onError(DioException error);

  /// Priority (lower runs first for onRequest, last for onResponse/onError)
  int get priority => 0;
}
```

### Chain Semantics

#### Short-Circuiting

```dart
// Abort request in onRequest
Future<RequestOptions> onRequest(RequestOptions options) async {
  if (!await hasValidToken()) {
    throw UnauthorizedException('No valid token');  // Stops chain, goes to onError
  }
  return options;
}

// Recover from error in onError
Future<dynamic> onError(DioException error) async {
  if (error.response?.statusCode == 401 && await refreshToken()) {
    // Retry with new token - return Response to recover
    return dio.fetch(error.requestOptions);
  }
  return error;  // Propagate error
}
```

#### Modification

```dart
// Add headers in onRequest
Future<RequestOptions> onRequest(RequestOptions options) async {
  options.headers['Authorization'] = 'Bearer ${await getToken()}';
  options.headers['X-Request-Id'] = uuid.v4();
  return options;
}

// Transform response in onResponse
Future<Response> onResponse(Response response) async {
  // Unwrap envelope
  if (response.data is Map && response.data['data'] != null) {
    response.data = response.data['data'];
  }
  return response;
}
```

### Priority Examples

```dart
// Recommended priority ordering:
const kLoggingPriority = 0;      // First: log raw request
const kAuthPriority = 10;        // Second: add auth headers
const kRetryPriority = 20;       // Third: retry wrapper
const kETagPriority = 30;        // Fourth: conditional request headers
const kMetricsPriority = 100;    // Last: timing/metrics
```

### Built-in Interceptors

#### AuthInterceptor

Injects authorization headers from a token provider.

```dart
class AuthInterceptor extends FetchInterceptor {
  final Future<String?> Function() tokenProvider;
  final String headerName;    // Default: 'Authorization'
  final String prefix;        // Default: 'Bearer '

  @override
  int get priority => 10;

  @override
  Future<RequestOptions> onRequest(RequestOptions options) async {
    final token = await tokenProvider();
    if (token != null) {
      options.headers[headerName] = '$prefix$token';
    }
    return options;
  }
}

// Usage:
AuthInterceptor(
  tokenProvider: () => authBloc.state.accessToken,
)
```

#### RefreshTokenInterceptor

Handles 401 responses with token refresh using singleflight pattern.

```dart
class RefreshTokenInterceptor extends FetchInterceptor {
  final Future<String?> Function() refreshToken;
  final Future<void> Function() onRefreshFailed;
  final Dio dio;  // For retry

  Completer<String>? _refreshInFlight;

  @override
  int get priority => 15;  // After auth, before retry

  @override
  Future<dynamic> onError(DioException error) async {
    if (error.response?.statusCode != 401) {
      return error;
    }

    // Singleflight: only one refresh at a time
    if (_refreshInFlight != null) {
      await _refreshInFlight!.future;
      return _retryRequest(error.requestOptions);
    }

    _refreshInFlight = Completer<String>();
    try {
      final newToken = await refreshToken();
      if (newToken == null) {
        await onRefreshFailed();
        return error;
      }
      _refreshInFlight!.complete(newToken);
      return _retryRequest(error.requestOptions);
    } catch (e) {
      _refreshInFlight!.completeError(e);
      await onRefreshFailed();
      return error;
    } finally {
      _refreshInFlight = null;
    }
  }
}

// Usage:
RefreshTokenInterceptor(
  dio: dio,
  refreshToken: () => authBloc.refreshAccessToken(),
  onRefreshFailed: () => authBloc.send(LogoutEvent()),
)
```

#### LoggingInterceptor

Logs requests and responses for debugging.

```dart
class LoggingInterceptor extends FetchInterceptor {
  final void Function(String) logger;
  final bool logBody;
  final bool logHeaders;

  @override
  int get priority => 0;  // First, sees raw request

  @override
  Future<RequestOptions> onRequest(RequestOptions options) async {
    logger('→ ${options.method} ${options.uri}');
    if (logHeaders) logger('  Headers: ${options.headers}');
    if (logBody && options.data != null) logger('  Body: ${options.data}');
    return options;
  }

  @override
  Future<Response> onResponse(Response response) async {
    logger('← ${response.statusCode} ${response.requestOptions.uri}');
    return response;
  }

  @override
  Future<dynamic> onError(DioException error) async {
    logger('✗ ${error.type} ${error.requestOptions.uri}');
    return error;
  }
}
```

#### RetryInterceptor

Implements retry with exponential backoff (respects idempotency rules).

```dart
class RetryInterceptor extends FetchInterceptor {
  final int maxRetries;
  final Duration Function(int attempt) backoff;
  final bool Function(DioException) shouldRetry;
  final Dio dio;

  @override
  int get priority => 20;

  @override
  Future<dynamic> onError(DioException error) async {
    final request = error.requestOptions;
    final attempt = (request.extra['_retryCount'] as int?) ?? 0;

    if (attempt >= maxRetries || !shouldRetry(error)) {
      return error;
    }

    // Check idempotency
    if (!_isIdempotent(request)) {
      return error;
    }

    await Future.delayed(backoff(attempt));
    request.extra['_retryCount'] = attempt + 1;
    return dio.fetch(request);
  }

  bool _isIdempotent(RequestOptions request) {
    final method = request.method.toUpperCase();
    if (['GET', 'HEAD', 'PUT', 'DELETE'].contains(method)) return true;
    // POST/PATCH only if explicitly marked retryable with idempotency key
    return request.extra['retryable'] == true &&
           request.extra['idempotencyKey'] != null;
  }
}
```

#### ETagInterceptor

Adds conditional request headers for cache validation.

```dart
class ETagInterceptor extends FetchInterceptor {
  final Future<String?> Function(String url) getETag;
  final Future<void> Function(String url, String etag) saveETag;

  @override
  int get priority => 30;

  @override
  Future<RequestOptions> onRequest(RequestOptions options) async {
    final etag = await getETag(options.uri.toString());
    if (etag != null) {
      options.headers['If-None-Match'] = etag;
    }
    return options;
  }

  @override
  Future<Response> onResponse(Response response) async {
    final etag = response.headers.value('etag');
    if (etag != null) {
      await saveETag(response.requestOptions.uri.toString(), etag);
    }
    return response;
  }
}
```

### Registering Interceptors

```dart
// At initialization
fetchBloc.send(InitializeFetchEvent(
  config: FetchConfig(baseUrl: 'https://api.example.com'),
  interceptors: [
    LoggingInterceptor(logger: print),
    AuthInterceptor(tokenProvider: () => authBloc.state.accessToken),
    RefreshTokenInterceptor(
      dio: dio,
      refreshToken: () => authBloc.refreshAccessToken(),
      onRefreshFailed: () => authBloc.send(LogoutEvent()),
    ),
    RetryInterceptor(
      maxRetries: 3,
      backoff: (attempt) => Duration(milliseconds: 500 * pow(2, attempt).toInt()),
      shouldRetry: (e) => e.type == DioExceptionType.connectionError,
      dio: dio,
    ),
  ],
));
```

### Interceptors vs Use Case Logic

| Concern | Where to Handle |
|---------|-----------------|
| Auth headers | `AuthInterceptor` |
| Token refresh | `RefreshTokenInterceptor` |
| Logging | `LoggingInterceptor` |
| Retry | `RetryInterceptor` |
| Cache policy | Use case (before interceptors) |
| Coalescing | Use case (before interceptors) |
| Decode | Use case (after interceptors) |
| State updates | Use case (emit) |

**Rule of thumb:** Interceptors handle transport concerns. Use cases handle application concerns.

---

## Error Types

### FetchError Hierarchy

```dart
sealed class FetchError extends JuiceException {
  final RequestKey? requestKey;
  final int? statusCode;
  final Duration? elapsed;
}

class NetworkError extends FetchError {
  /// No connectivity
}

class TimeoutError extends FetchError {
  /// Request timed out
  final TimeoutType type; // connect, send, receive
}

class HttpError extends FetchError {
  /// Server returned error status
  final int statusCode;
  final dynamic responseBody;
}

class ClientError extends HttpError {
  /// 4xx errors
}

class ServerError extends HttpError {
  /// 5xx errors (retryable)
  @override
  bool get isRetryable => true;
}

class DecodeError extends FetchError {
  /// JSON decode or type conversion failed
  final Type expectedType;
  final dynamic actualValue;
}

class CancelledError extends FetchError {
  /// Request was cancelled
  final String? reason;
}
```

---

## Configuration

### FetchConfig (Platform-Neutral)

Config values that work identically on all platforms:

```dart
@immutable
class FetchConfig {
  /// Base URL for all requests
  final String? baseUrl;

  /// Default timeout for connection
  final Duration connectTimeout;

  /// Default timeout for receiving data
  final Duration receiveTimeout;

  /// Default cache policy
  final CachePolicy defaultCachePolicy;

  /// Default TTL for cached responses
  final Duration? defaultTtl;

  /// Maximum cache size in bytes
  final int maxCacheSize;

  /// Maximum concurrent requests
  final int maxConcurrentRequests;

  /// Default headers for all requests
  final Map<String, String> defaultHeaders;

  /// Whether to follow redirects
  final bool followRedirects;

  /// Maximum redirects to follow
  final int maxRedirects;

  const FetchConfig({
    this.baseUrl,
    this.connectTimeout = const Duration(seconds: 30),
    this.receiveTimeout = const Duration(seconds: 30),
    this.defaultCachePolicy = CachePolicy.networkFirst,
    this.defaultTtl,
    this.maxCacheSize = 50 * 1024 * 1024, // 50 MB
    this.maxConcurrentRequests = 10,
    this.defaultHeaders = const {},
    this.followRedirects = true,
    this.maxRedirects = 5,
  });
}
```

### PlatformConfig (Platform-Specific)

Options that only apply to certain platforms. Injected via `InitializeFetchEvent`:

```dart
@immutable
class PlatformConfig {
  // === Mobile/Desktop Only ===

  /// Certificate pinning configuration
  /// Ignored on web (browser manages TLS)
  final CertificatePinConfig? certificatePinning;

  /// Custom HTTP adapter (e.g., Http2Adapter for HTTP/2)
  /// Ignored on web
  final HttpClientAdapter? httpAdapter;

  /// Proxy configuration
  /// Ignored on web
  final ProxyConfig? proxy;

  // === Web Only ===

  /// Include credentials (cookies) in CORS requests
  /// Ignored on mobile/desktop
  final bool withCredentials;

  const PlatformConfig({
    this.certificatePinning,
    this.httpAdapter,
    this.proxy,
    this.withCredentials = false,
  });

  /// Whether running on web platform
  static bool get isWeb => identical(0, 0.0);  // Compile-time web detection
}

@immutable
class CertificatePinConfig {
  final String host;
  final List<String> sha256Fingerprints;

  const CertificatePinConfig({
    required this.host,
    required this.sha256Fingerprints,
  });
}
```

### InitializeFetchEvent (Complete)

```dart
class InitializeFetchEvent extends FetchEvent {
  /// Platform-neutral configuration
  final FetchConfig config;

  /// Platform-specific configuration
  final PlatformConfig? platformConfig;

  /// Custom interceptors
  final List<FetchInterceptor>? interceptors;

  const InitializeFetchEvent({
    this.config = const FetchConfig(),
    this.platformConfig,
    this.interceptors,
  });
}
```

---

## Public API

### Convenience Methods on FetchBloc

```dart
extension FetchBlocExtensions on FetchBloc {
  /// GET request with JSON response
  Future<T?> getJson<T>(
    String url, {
    Map<String, dynamic>? queryParams,
    T Function(Map<String, dynamic>)? decode,
    CachePolicy? cachePolicy,
    Duration? ttl,
    Set<String>? groupsToRebuild,
    String? scope,
  }) {
    final event = GetEvent<T>(
      url: url,
      queryParams: queryParams,
      decode: decode,
      cachePolicy: cachePolicy ?? state.config.defaultCachePolicy,
      ttl: ttl,
      groupsToRebuild: groupsToRebuild,
      scope: scope,
    );
    send(event);
    return event.result;
  }

  /// POST request with JSON body and response
  Future<T?> postJson<T>(
    String url,
    Object body, {
    T Function(Map<String, dynamic>)? decode,
    Set<String>? groupsToRebuild,
    String? scope,
  });

  /// PUT request
  Future<T?> putJson<T>(...);

  /// PATCH request
  Future<T?> patchJson<T>(...);

  /// DELETE request
  Future<T?> deleteJson<T>(...);

  /// Invalidate cache for a specific key or pattern
  Future<void> invalidate({RequestKey? key, String? urlPattern});

  /// Clear all cached responses
  Future<void> clearCache({String? namespace});

  /// Cancel requests by key or scope
  void cancel({RequestKey? key, String? scope});

  /// Get a cancel token for a scope
  CancelToken cancelToken(String scope);
}
```

---

## Rebuild Groups

| Group Pattern | Description |
|---------------|-------------|
| `fetch:request:{key}` | Specific request by canonical key |
| `fetch:url:{pattern}` | All requests matching URL pattern |
| `fetch:inflight` | When inflight count changes |
| `fetch:cache` | When cache stats change |
| `fetch:error` | When an error occurs |
| `fetch:config` | When configuration changes |

---

## Cross-Bloc Integration

### With LifecycleBloc (core juice)

FetchBloc subscribes to `LifecycleBloc.notifications` for automatic request cancellation when feature scopes end. This is a **required** integration.

```dart
class FetchBloc extends JuiceBloc<FetchState> {
  StreamSubscription<ScopeNotification>? _lifecycleSubscription;

  FetchBloc() : super(FetchState.initial()) {
    // Subscribe to scope lifecycle - auto-cancel requests when scopes end
    _lifecycleSubscription = BlocScope.get<LifecycleBloc>()
        .notifications
        .whereType<ScopeEndingNotification>()
        .listen(_onScopeEnding);
  }

  void _onScopeEnding(ScopeEndingNotification notification) {
    // Cancel all requests tagged with this scope
    send(CancelScopeEvent(scope: notification.scopeName));

    // Optionally register cleanup with the barrier for async cancellation
    notification.barrier.add(_cancelInflightForScope(notification.scopeName));
  }

  Future<void> _cancelInflightForScope(String scope) async {
    // Cancel logic here
  }

  @override
  Future<void> close() async {
    await _lifecycleSubscription?.cancel();
    await super.close();
  }
}
```

**What this does:**
1. When any `FeatureScope.end()` is called
2. `LifecycleBloc` publishes `ScopeEndingNotification` with a `CleanupBarrier`
3. FetchBloc receives it via the notifications stream
4. Sends `CancelScopeEvent(scope: scopeName)` to itself
5. All inflight requests with matching scope are cancelled
6. Optionally adds async cleanup to the barrier so scope waits for cancellation

### With StorageBloc

```dart
// Cache persistence
StateRelay<StorageState, FetchEvent>(
  sourceBloc: storageBloc,
  transform: (storageState) => null, // FetchBloc reads on demand
);

// Token retrieval
final token = await storageBloc.secureRead('auth_token');
```

### With ConnectivityBloc (future)

```dart
StateRelay<ConnectivityState, FetchEvent>(
  sourceBloc: connectivityBloc,
  transform: (connectivityState) {
    if (!connectivityState.hasInternet) {
      return PauseRequestsEvent();
    } else if (connectivityState.justReconnected) {
      return FlushQueueEvent();
    }
    return null;
  },
);
```

### With AuthBloc (future)

```dart
EventSubscription<AuthEvent, FetchEvent>(
  sourceBloc: authBloc,
  transform: (authEvent) {
    if (authEvent is LogoutEvent) {
      return ClearCacheEvent(namespace: 'user');
    }
    if (authEvent is TokenRefreshedEvent) {
      return RetryFailedAuthEvent();
    }
    return null;
  },
);
```

---

## Demo App: Fetch Arcade

### Demo Purity Requirements

The demo must teach Juice patterns correctly. **Strict rules:**

| Allowed | Not Allowed |
|---------|-------------|
| `StatelessJuiceWidget` for all UI | `setState` / `StatefulWidget` |
| Bloc state for form inputs | Local widget state |
| `StatelessJuiceWidget` for all fetch results | `FutureBuilder` / `StreamBuilder` for network |
| Bloc events trigger all fetches | Direct `dio.get()` calls |

**The rule:** All state lives in blocs. Widgets are stateless and rebuild via groups.

Every "result", "inflight", "error", "cache status" display must come from `StatelessJuiceWidget` with appropriate rebuild groups.

### Screens

1. **Request Playground**
   - URL input field → bloc state
   - Method selector → bloc state
   - Cache policy dropdown → bloc event on change
   - TTL slider → bloc state
   - Execute button → sends `GetEvent`/`PostEvent`
   - Response viewer → `StatelessJuiceWidget` with `fetch:request:{key}` group

2. **Dedupe Demo**
   - "Fetch 10x" button → 10 events, shows 1 network call
   - Counter shows all 10 completers resolving
   - Visual: 10 widgets all showing same loading → same result
   - Each widget is a `StatelessJuiceWidget` with same group

3. **Cache Demo**
   - Toggle between cache policies → bloc events
   - Visual cache hit/miss indicator → `StatelessJuiceWidget` with `fetch:cache` group
   - Stale-while-revalidate: show stale immediately, flash on refresh
   - TTL countdown display

4. **Error Simulation**
   - Toggle to simulate 500 errors
   - Toggle to simulate timeouts
   - Show retry backoff visually (attempt counter, delay)
   - Show fallback to cache when `networkFirst` fails
   - All state from `StatelessJuiceWidget` with `fetch:error`, `fetch:request:{key}` groups

5. **Inspector**
   - Event log (like StorageBloc arcade)
   - Active requests list → `StatelessJuiceWidget` with `fetch:inflight` group
   - Cache entries browser → reads from StorageBloc
   - Network stats dashboard → `StatelessJuiceWidget` with `fetch:stats` group

### Architecture

```dart
/// Demo bloc coordinates UI state, delegates network to FetchBloc
class FetchArcadeBloc extends JuiceBloc<FetchArcadeState> {
  final FetchBloc fetchBloc;

  FetchArcadeBloc({required this.fetchBloc}) : super(FetchArcadeState.initial()) {
    // StateRelay to react to fetch state changes
    addRelay(StateRelay<FetchState, FetchArcadeEvent>(
      sourceBloc: fetchBloc,
      transform: (fetchState) {
        // Transform fetch state to arcade events if needed
        return null;
      },
    ));
  }
}

/// UI state for the demo - NOT network state
@immutable
class FetchArcadeState extends BlocState {
  final String currentUrl;
  final String selectedMethod;
  final CachePolicy selectedPolicy;
  final Duration selectedTtl;
  final bool simulateErrors;
  final bool simulateTimeout;
  final List<DemoEvent> eventLog;

  // NO: isLoading, response, error - these come from FetchBloc
}
```

**Widget pattern:**

```dart
/// Each widget subscribes to same group - all rebuild together
class DedupeDemoItem extends StatelessJuiceWidget<FetchBloc> {
  final int widgetId;

  DedupeDemoItem({super.key, required this.widgetId})
      : super(groups: {'fetch:request:demo-key'});

  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    final requestStatus = bloc.state.activeRequests['demo-key'];
    if (requestStatus?.phase == RequestPhase.inflight) {
      return LoadingWidget(widgetId: widgetId);
    }
    // All 10 show same result simultaneously
    return ResultWidget(widgetId: widgetId, data: bloc.state.lastResponses['demo-key']);
  }
}

/// Parent just lays out 10 instances
class DedupeDemo extends StatelessJuiceWidget<FetchBloc> {
  DedupeDemo({super.key}) : super(groups: optOutOfRebuilds);

  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    return Column(
      children: [
        for (var i = 0; i < 10; i++)
          DedupeDemoItem(widgetId: i),
      ],
    );
  }
}
```

---

## File Structure

```
packages/juice_network/
├── lib/
│   ├── juice_network.dart           # Exports
│   └── src/
│       ├── fetch_bloc.dart          # Main bloc
│       ├── fetch_state.dart         # State classes
│       ├── fetch_events.dart        # Event classes
│       ├── fetch_config.dart        # Configuration
│       ├── fetch_exceptions.dart    # Error types
│       ├── cache/
│       │   ├── cache_policy.dart
│       │   ├── cache_entry.dart
│       │   └── cache_manager.dart
│       ├── request/
│       │   ├── request_key.dart
│       │   ├── request_status.dart
│       │   └── request_coalescer.dart
│       ├── interceptors/
│       │   ├── interceptor.dart
│       │   ├── auth_interceptor.dart
│       │   ├── logging_interceptor.dart
│       │   ├── retry_interceptor.dart
│       │   └── etag_interceptor.dart
│       └── use_cases/
│           ├── initialize_use_case.dart
│           ├── execute_request_use_case.dart
│           ├── cancel_use_case.dart
│           └── cache_use_cases.dart
├── test/
├── example/
│   └── lib/
│       ├── main.dart
│       ├── blocs/
│       │   ├── fetch_arcade_bloc.dart
│       │   ├── fetch_arcade_state.dart
│       │   └── fetch_arcade_events.dart
│       └── screens/
│           ├── playground_screen.dart
│           ├── dedupe_demo_screen.dart
│           ├── cache_demo_screen.dart
│           └── inspector_screen.dart
├── doc/
│   ├── SPEC.md                      # This document
│   ├── getting-started.md
│   ├── cache-policies.md
│   ├── interceptors.md
│   └── testing.md
├── pubspec.yaml
├── CHANGELOG.md
├── LICENSE
└── README.md
```

---

## Dependencies

```yaml
dependencies:
  flutter:
    sdk: flutter
  juice: ^1.2.0
  juice_storage: ^1.0.0  # For cache persistence
  dio: ^5.4.0
  crypto: ^3.0.3         # For body hashing

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^4.0.0
  mocktail: ^1.0.4
  http_mock_adapter: ^0.6.0
```

---

## Version History

| Version | Status | Notes |
|---------|--------|-------|
| 0.1.0 | Planned | Initial release with core functionality |

---

## Platform Strategy

### HTTP Client Abstraction

FetchBloc uses Dio as the HTTP client, which handles platform differences internally:

| Platform | Transport |
|----------|-----------|
| Mobile (iOS/Android) | `dart:io` HttpClient |
| Desktop (macOS/Windows/Linux) | `dart:io` HttpClient |
| Web | `dart:html` HttpRequest / Fetch API |

### Platform-Specific Considerations

#### All Platforms
- Request/response interceptors work identically
- Caching via StorageBloc (Hive) works on all platforms
- Cancel tokens work on all platforms

#### Mobile/Desktop Only
- Certificate pinning (via Dio's `badCertificateCallback`)
- Custom DNS resolution
- HTTP/2 support (with dio_http2_adapter)
- Client certificates for mTLS

#### Web Limitations
- No certificate pinning (browser controls TLS)
- CORS restrictions apply
- Cookies managed by browser (not accessible to Dart)
- No custom DNS
- Request body size limits may apply

### Configuration by Platform

```dart
FetchConfig(
  // Works everywhere
  baseUrl: 'https://api.example.com',
  connectTimeout: Duration(seconds: 30),

  // Mobile/Desktop only - ignored on web
  certificatePinning: CertificatePinConfig(
    host: 'api.example.com',
    sha256Fingerprints: ['abc123...'],
  ),

  // Web only - ignored on mobile/desktop
  withCredentials: true,  // Include cookies in CORS requests
);
```

### Dio Adapters

Default: Dio's built-in adapter (platform-appropriate).

Optional adapters (mobile/desktop):
- `dio_http2_adapter` for HTTP/2
- Custom adapter for advanced proxy/certificate needs

```dart
InitializeFetchEvent(
  config: FetchConfig(...),
  httpAdapter: Http2Adapter(),  // Optional, mobile/desktop only
);
```

---

## Decisions (Resolved)

These questions have been resolved for v0.1.0:

### 1. Naming: FetchBloc

**Decision:** Use `FetchBloc`.

- Communicates intent: request/response + caching + coalescing
- "NetworkBloc" sounds like connectivity/DNS/socket state
- "RemoteBloc" is vague and invites scope creep

Package remains `juice_network`, bloc is `FetchBloc`.

### 2. Offline Queue: Deferred to v0.2+

**Decision:** Spec the interface now, implement later.

Reason: Offline queue implies ordering, conflict strategy, persistence, replay triggers, and idempotency keys — would balloon v0.1.0.

Future `Outbox` concept:
- `QueuePolicy.none | memory | persistent`
- Writes only, explicit opt-in
- Idempotency key required

### 3. Multipart Uploads: Basic Support in Core

**Decision:** Keep thin support in-core, advanced features later.

v0.1.0 includes:
- `RequestBody.bytes`
- `RequestBody.stream`
- `RequestBody.multipart` (basic)

v0.2+ or `juice_upload`:
- Progress reporting
- Resumable uploads
- Chunked uploads

### 4. WebSocket: Separate Package

**Decision:** Yes, create `juice_realtime` separately.

WebSockets change everything:
- Connection lifecycle (persistent, not request/response)
- Reconnection with backoff
- Heartbeats/ping-pong
- Backpressure handling
- Streams vs futures

Shared with FetchBloc:
- Auth interceptors
- Connectivity signals

### 5. GraphQL: Separate Package

**Decision:** Yes, create `juice_graphql` separately.

FetchBloc is GraphQL-friendly by design:
- Easy header injection
- POST JSON body canonical hashing
- operationName/query/variables included via bodyHash

`juice_graphql` will be thin:
- Typed query/mutation helpers
- Fragment handling
- Subscription (via juice_realtime)

---

## Appendix: Test Scenarios

### Canonicalization Tests

```dart
test('query params are sorted', () {
  final key1 = RequestKey.from(url: '/api?z=1&a=2');
  final key2 = RequestKey.from(url: '/api?a=2&z=1');
  expect(key1.canonical, equals(key2.canonical));
});

test('repeated params are sorted by value', () {
  final key1 = RequestKey.from(url: '/api?a=2&a=1');
  final key2 = RequestKey.from(url: '/api?a=1&a=2');
  expect(key1.canonical, equals(key2.canonical));
});

test('json bodies with different key order hash same', () {
  final key1 = RequestKey.from(
    method: 'POST',
    url: '/api',
    body: {'b': 1, 'a': 2},
  );
  final key2 = RequestKey.from(
    method: 'POST',
    url: '/api',
    body: {'a': 2, 'b': 1},
  );
  expect(key1.canonical, equals(key2.canonical));
});
```

### Coalescing Tests

```dart
test('5 simultaneous requests result in 1 network call', () async {
  var networkCallCount = 0;

  // Mock Dio to count actual calls
  when(() => dio.get(any())).thenAnswer((_) async {
    networkCallCount++;
    await Future.delayed(Duration(milliseconds: 100));
    return Response(data: 'result', statusCode: 200);
  });

  // Fire 5 requests simultaneously
  final futures = List.generate(5, (_) =>
    fetchBloc.getJson('/api/data')
  );

  final results = await Future.wait(futures);

  expect(networkCallCount, equals(1));
  expect(results, everyElement(equals('result')));
});
```

### Cache Safety Tests

```dart
test('does not cache authorized requests by default', () async {
  fetchBloc.send(GetEvent(
    url: '/api/profile',
    cachePolicy: CachePolicy.cacheFirst,
    headers: {'Authorization': 'Bearer token'},
  ));

  await Future.delayed(Duration.zero);

  // Verify no cache entry created
  final cached = await storageBloc.hiveRead('_fetch_cache', key);
  expect(cached, isNull);
});

test('caches authorized requests when opted in', () async {
  fetchBloc.send(GetEvent(
    url: '/api/profile',
    cachePolicy: CachePolicy.cacheFirst,
    headers: {'Authorization': 'Bearer token'},
    cacheAuthResponses: true,
  ));

  await Future.delayed(Duration.zero);

  final cached = await storageBloc.hiveRead('_fetch_cache', key);
  expect(cached, isNotNull);
});
```

### Retry Safety Tests

```dart
test('does not retry POST by default', () async {
  var callCount = 0;
  when(() => dio.post(any(), data: any(named: 'data')))
    .thenAnswer((_) async {
      callCount++;
      throw DioException(type: DioExceptionType.connectionError);
    });

  await expectLater(
    fetchBloc.postJson('/api/orders', {'item': 'widget'}),
    throwsA(isA<NetworkError>()),
  );

  expect(callCount, equals(1)); // No retry
});

test('retries POST when explicitly opted in with idempotency key', () async {
  var callCount = 0;
  when(() => dio.post(any(), data: any(named: 'data')))
    .thenAnswer((_) async {
      callCount++;
      if (callCount < 3) {
        throw DioException(type: DioExceptionType.connectionError);
      }
      return Response(data: {'id': 123}, statusCode: 201);
    });

  final result = await fetchBloc.postJson(
    '/api/orders',
    {'item': 'widget'},
    retryable: true,
    idempotencyKey: 'order-abc',
  );

  expect(callCount, equals(3));
  expect(result['id'], equals(123));
});
```

---

## Freeze Checklist

Before marking spec as frozen for v0.1.0, verify all items:

### Model Completeness

- [x] `RequestKey` implements value equality via `==` and `hashCode` based on `canonical`
- [x] `RequestKey` includes `headerVaryHash` for identity-affecting headers
- [x] `RequestStatus` includes `scope` field for grouped cancellation
- [x] `WireCacheRecord` stores raw bytes, not decoded types
- [x] `RequestEvent` includes all knobs: `cacheAuthResponses`, `forceCache`, `retryable`, `idempotencyKey`, `allowStaleOnError`
- [x] `PlatformConfig` separates platform-specific options from `FetchConfig`

### Behavioral Correctness

- [x] Coalescer is authoritative; `FetchState.activeRequests` is observability
- [x] Persistent cache stores wire response (bytes + headers), decode happens per-caller
- [x] POST/PATCH retry requires explicit `retryable: true` + `idempotencyKey`
- [x] Token refresh uses singleflight pattern (one refresh, others await)
- [x] SWR background refresh coalesces but bypasses cache read
- [x] Cache eviction defined: LRU by `cachedAt`, triggered on write

### Safety Rules

- [x] Authorization responses not cached by default (`cacheAuthResponses` required)
- [x] Sensitive endpoints (`/auth/*`, `/login`) never cached
- [x] `Cache-Control: no-store` respected unless `forceCache: true`
- [x] Idempotent-only retry (GET/HEAD/PUT/DELETE default, POST/PATCH explicit)

### Canonicalization

- [x] Query params sorted by key, then value
- [x] Repeated query params preserved, sorted
- [x] JSON body uses canonical JSON (sorted keys, no whitespace)
- [x] Only identity headers in hash (Accept, Content-Type, X-Api-Version, Accept-Language)
- [x] `authScope` captures auth identity without token value

### Platform

- [x] `FetchConfig` is platform-neutral
- [x] `PlatformConfig` handles mobile/desktop vs web differences
- [x] Certificate pinning documented as mobile/desktop only
- [x] CORS `withCredentials` documented as web only

---

## Spec Version

| Version | Date | Status | Changes |
|---------|------|--------|---------|
| 1.0 | - | Draft | Initial spec |
| 1.1 | - | Pre-freeze | Added canonicalization rules, coalescing semantics, cache safety, retry correctness, freeze checklist |
| 1.2 | - | Pre-freeze | Refined "Why Use FetchBloc?" with 5 problems / 6 solutions framing; positioning as remote-state contract |
| 1.3 | - | Pre-freeze | Fixed Juice patterns (StatelessJuiceWidget, BlocUseCase, Set groups, EventBase); Added LifecycleBloc integration |
| 1.4 | - | **Frozen** | Ready for v0.1.0 implementation |
