---
card_schema: "1.0"
package: juice_network
version: 0.12.0
requires:
  juice: ">=1.4.0"
  juice_storage: ">=1.2.0"
updated: 2026-06-09
---

# juice_network — AI card

> Network foundation bloc: HTTP via fire-and-forget request *events*, with
> deterministic request identity, wire-level coalescing, policy-driven caching,
> a typed `FetchError` hierarchy, retries, and an interceptor pipeline. Read repo
> `AGENTS.md` for the Juice mental model + gotchas.

## Purpose

**Owns:** the remote-I/O contract — request identity (`RequestKey`), inflight
coalescing, the cache (raw wire bytes via `juice_storage`), typed errors, retry,
and the interceptor chain.
**Does NOT own:** the transport itself (Dio is injected), the offline write
outbox (`juice_sync`), live streams (`juice_realtime`), or auth credentials
(supply an `AuthInterceptor` + `AuthIdentityProvider`, e.g. via
`juice_auth_network`).

## When to use

5+ screens making HTTP calls, or you need caching / loading states / typed
errors / dedup / observability. A single endpoint utility can just use Dio.

## Install

```yaml
dependencies:
  juice_network: ^0.12.0
  juice_storage: ^1.2.0   # required — cache persistence
  dio: ^5.4.0             # the injected transport
```

**Prerequisite:** register `ScopeLifecycleBloc` (core juice) *before* `FetchBloc`
so scope-based auto-cancel works. `StorageBloc` must also be registered/passed.

## Construct

`storageBloc` is **required** (cache persistence). Dio is optional (a default
`Dio()` is created). If any interceptor injects auth, you **must** also pass
`authIdentityProvider` or cache/coalescing will leak responses across users.

```dart
final fetch = FetchBloc.withConfig(
  const FetchConfig(baseUrl: 'https://api.example.com'),
  storageBloc: storageBloc,
  dio: dio,                                   // optional
  authIdentityProvider: () => authBloc.state.userId,  // String? Function()
  interceptors: [AuthInterceptor(tokenProvider: () async => token)],
);
// Equivalent to: FetchBloc(...) then send(InitializeFetchEvent(config, interceptors)).
```

## Seams

```dart
// User identity for cache/coalescing keys. REQUIRED when auth is injected.
typedef AuthIdentityProvider = String? Function();
//  user id / hashed email / session id — stable per session
//  null → unauthenticated (uses the shared/unscoped cache)

// Transport: a Dio instance is injected (vendor seam). Default = new Dio().

// Interceptor pipeline. Subclass FetchInterceptor; lower priority runs first
// on onRequest, last (reverse) on onResponse/onError.
abstract class FetchInterceptor {
  Future<RequestOptions> onRequest(RequestOptions o) async => o;   // throw → onError chain
  Future<Response> onResponse(Response r) async => r;              // throw → convert to error
  Future<dynamic> onError(DioException e) async => e;              // return Response → recover
  int get priority => 0;                                           // see InterceptorPriority
}
// Shipped impls: AuthInterceptor, ApiKeyInterceptor, RetryInterceptor,
// RefreshTokenInterceptor (singleflight 401 refresh), LoggingInterceptor, ETagInterceptor.
```

## API

Construction-time convenience (`FetchBloc`); all request work is via **events**
(send-and-forget; results land in state + cache, observed by rebuild group):

```dart
factory FetchBloc.withConfig(FetchConfig config, {required StorageBloc storageBloc,
    Dio? dio, AuthIdentityProvider? authIdentityProvider, List<FetchInterceptor>? interceptors});
Future<void> acquireConcurrencySlot();   // internal: maxConcurrentRequests gate
void releaseConcurrencySlot();
```

## Events

Requests are **non-generic** events carrying a `decode` callback (not awaitable
`ResultEvent`s — the SPEC's `GetEvent<T>`/`event.result` shape is aspirational;
the code is the source of truth). Decoded value + status flow to state under the
`fetch:request:<canonical>` group.

| Event | Effect / default cache policy |
|---|---|
| `InitializeFetchEvent(config, interceptors?)` | configure Dio + interceptors; `isInitialized=true` |
| `ResetFetchEvent(clearCache, cancelInflight, resetStats)` | return to baseline |
| `ReconfigureInterceptorsEvent(interceptors)` | rebuild the Dio interceptor chain (priority-sorted) |
| `GetEvent(url, decode?, cachePolicy?, ttl?, scope?, …)` | GET; default policy = `config.defaultCachePolicy` (`networkFirst`); `retryable=true` |
| `PostEvent(url, body?, idempotencyKey?, …)` | POST; default `networkOnly`; `retryable=false` (retry needs `idempotencyKey`) |
| `PutEvent` / `PatchEvent` / `DeleteEvent` / `HeadEvent` | mutation/read; mutations default `networkOnly` |
| `InvalidateCacheEvent(key?, urlPattern?, namespace?)` | drop matching cache entries |
| `ClearCacheEvent(namespace?)` · `PruneCacheEvent(targetBytes?)` · `CleanupExpiredCacheEvent` | cache maintenance |
| `CancelRequestEvent(key)` · `CancelScopeEvent(scope)` · `CancelAllEvent` | cancel → callers see `CancelledError` |
| `ResetStatsEvent` *internal-ish* · `ClearLastErrorEvent` | observability |

## State

```dart
class FetchState extends BlocState {        // immutable
  bool isInitialized; FetchConfig config;
  Map<String, RequestStatus> activeRequests;   // keyed by RequestKey.canonical
  int inflightCount; NetworkStats stats; CacheStats cacheStats;
  FetchError? lastError;
  bool isActive(RequestKey) ; bool isInflight(RequestKey); RequestStatus? getStatus(RequestKey);
  bool get hasInflight; bool get hasError;
}
// RequestPhase { queued, inflight, completed, failed, cancelled }
// NetworkStats: totalRequests/successCount/failureCount/cacheHits/cacheMisses/
//   retryCount/coalescedCount/bytes… + avgResponseTimeMs/hitRate/successRate getters
```

## Rebuild groups

| Group | Emitted when |
|---|---|
| `FetchGroups.config` → `fetch:config` | initialized / reconfigured |
| `FetchGroups.inflight` → `fetch:inflight` | inflight set / count changed |
| `FetchGroups.cache` → `fetch:cache` | cache mutated |
| `FetchGroups.statsGroup` → `fetch:stats` | stats updated (frequent) |
| `FetchGroups.error` → `fetch:error` | `lastError` set/cleared |
| `FetchGroups.request(canonical)` → `fetch:request:<canonical>` | one request's phase/result changed |
| `FetchGroups.url(pattern)` → `fetch:url:<pattern>` | requests matching a URL pattern |

A request event with explicit `groupsToRebuild` emits *those* instead of the
default `fetch:request:<canonical>` — pass your own to drive a specific widget.

## Recipes

```dart
// 1. Consume — send the event, bind a widget to its key group.
final key = RequestKey.from(method: 'GET', url: '/users/123');
fetch.send(GetEvent(url: '/users/123', decode: User.fromJson,
    cachePolicy: CachePolicy.staleWhileRevalidate, scope: 'profile'));

class UserTile extends StatelessJuiceWidget<FetchBloc> {
  UserTile({super.key, required this.key2}) : super(groups: {FetchGroups.request(key2.canonical)});
  final RequestKey key2;
  @override Widget onBuild(BuildContext c, StreamStatus s) {
    final st = bloc.state.getStatus(key2);
    return Text(st?.phase == RequestPhase.inflight ? '…' : 'loaded');
  }
}

// 2. Vendor adapter for the interceptor seam (auth header).
class BearerInterceptor extends FetchInterceptor {
  BearerInterceptor(this.token);
  final Future<String?> Function() token;
  @override int get priority => InterceptorPriority.auth;
  @override Future<RequestOptions> onRequest(RequestOptions o) async {
    final t = await token();
    if (t != null) o.headers['Authorization'] = 'Bearer $t';
    return o;
  }
}

// 3. Auto-cancel on screen teardown (scope-tagged requests).
@override void dispose() { fetch.send(CancelScopeEvent(scope: 'profile')); super.dispose(); }
```

## Testing

Headless — inject a Dio backed by `http_mock_adapter`, an in-memory/fake
`StorageBloc`, and assert on `bloc.state` + emitted groups.

```dart
final dio = Dio()..httpClientAdapter = DioAdapter(dio: dio);
final fetch = FetchBloc.withConfig(const FetchConfig(), storageBloc: fakeStorage, dio: dio);
(dio.httpClientAdapter as DioAdapter).onGet('/x', (s) => s.reply(200, {'ok': true}));
fetch.send(GetEvent(url: '/x'));
await settle();                                    // Future.delayed(20ms)
expect(fetch.state.stats.successCount, 1);
```

## Failure modes

- All failures are typed `FetchError` subtypes — never raw `DioException`:
  `NetworkError`, `TimeoutError` (connect/send/receive), `HttpError`
  (`ClientError` 4xx / `ServerError` 5xx), `DecodeError`, `CancelledError`.
- `HttpError.isRetryable` → true for 5xx (except 501) and 429; 4xx is not.
- Decode errors are **isolated** — a bad decoder throws `DecodeError` for that
  caller only; the raw wire cache stays valid (other callers/types unaffected).
- Background `staleWhileRevalidate` refresh failures are **silent** — stale data
  is still served (the one intentional swallow; everything else surfaces in
  `lastError`).
- Coalescing is wire-level: N callers of the same `RequestKey.canonical` share
  one network call; a shared failure propagates to all of them.

## Anti-patterns

- ❌ Injecting an `AuthInterceptor` without an `authIdentityProvider` — cached
  responses leak across users after logout/login on the same device.
- ❌ Treating a request event as awaitable (`await event.result`) — it isn't;
  observe the `fetch:request:<canonical>` group / `state.getStatus(key)`.
- ❌ `retryable: true` on `PostEvent`/`PatchEvent` without an `idempotencyKey` —
  non-idempotent retry can double-apply.
- ❌ Caching auth-protected responses — off by default; only `cacheAuthResponses:
  true` (and never for `/auth/*`, `Set-Cookie`, `no-store` without `forceCache`).
- ❌ Putting `T` into the cache key — the cache stores raw bytes so the same URL
  decodes to different types without fragmenting.

## Integrates with

- **juice_storage** — required; the cache persists `WireCacheRecord` bytes.
- **juice_auth** via **juice_auth_network** — `AuthBlocAuthInterceptor`,
  `AuthBlocRefreshInterceptor`, `AuthBlocIdentityProvider` wire auth in.
- **juice** `ScopeLifecycleBloc` — feature scope ending auto-cancels its requests.

## Invariants

- **`RequestKey` value-equality by `canonical`** (method+URL+sorted query+
  bodyHash+identity-headers+authScope+variant). Without it, coalescing/cache fail
  silently.
- **`activeRequests` is observability**; the `RequestCoalescer._inflight` map is
  authoritative for dedup.
- **`close()`** cancels the lifecycle subscription, coalescer, and queued slots.
- Deferred (not in this version): an offline outbox (`Pause/Resume/Enqueue`
  events) — use `juice_sync`.

## See also

`doc/SPEC.md` (design depth — note code-over-spec divergences) ·
`doc/caching.md` · `doc/coalescing.md` · `doc/errors.md` ·
`doc/interceptors.md` · repo `AGENTS.md` (framework).
