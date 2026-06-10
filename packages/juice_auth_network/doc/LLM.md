---
card_schema: "1.0"
package: juice_auth_network
version: 0.1.1
requires:
  juice: ">=1.4.0"
  juice_auth: ">=0.2.1"
  juice_network: ">=0.12.0"
updated: 2026-06-09
---

# juice_auth_network — AI card

> **Glue** package: wires `AuthBloc` (juice_auth) into `FetchBloc`
> (juice_network) so authenticated requests, 401 refresh, and per-user cache
> isolation work with no hand-written plumbing. Adapters only — no new domain,
> no bloc, no state. Read repo `AGENTS.md` for the Juice mental model.

## Purpose

**Owns:** three adapters that translate `AuthBloc` state/actions into the seams
`juice_network` already exposes.
**Does NOT own:** auth logic (juice_auth) or network logic (juice_network) — it
only bridges them. It adds no events, state, or rebuild groups of its own.

## Install

```yaml
dependencies:
  juice_auth_network: ^0.1.0
  juice_auth: ^0.2.1
  juice_network: ^0.11.0
  # juice_storage + dio come in transitively via the two packages above
```

## Construct

There is nothing to construct here — you build a `FetchBloc` as usual and feed it
the three adapters:

```dart
final dio = Dio();
final fetchBloc = FetchBloc(
  storageBloc: storageBloc,
  dio: dio,                                              // refresh interceptor needs this Dio
  authIdentityProvider: AuthBlocIdentityProvider(authBloc).call,   // per-user cache scope
);
fetchBloc.send(InitializeFetchEvent(
  config: const FetchConfig(baseUrl: 'https://api.example.com'),
  interceptors: [
    AuthBlocAuthInterceptor(authBloc),                  // inject current access token
    AuthBlocRefreshInterceptor(authBloc, dio: dio),     // 401 → AuthBloc refresh → retry
  ],
));
```

## What it wires

| Adapter | Bridges | Mechanism |
|---|---|---|
| `AuthBlocIdentityProvider(authBloc)` | `AuthBloc` → `AuthIdentityProvider` (`String? Function()`) | `.call()` returns `authBloc.state.userId` (or `null`). Pass as `authIdentityProvider: provider.call`. **Required** when injecting auth, or cached responses leak across users. |
| `AuthBlocAuthInterceptor(authBloc, {headerName, prefix, skipAuth})` | `AuthBloc` → `AuthInterceptor` | `tokenProvider: () async => authBloc.state.session?.accessToken`. No session → no `Authorization` header. Reads the token per request, so it's always current after a refresh. |
| `AuthBlocRefreshStrategy(authBloc, {timeout})` | `AuthBloc.refreshToken()` (fire-and-forget) → `Future<String?> Function()` | Subscribes to `authBloc.stream`, triggers refresh, resolves with the new `accessToken` when `isRefreshing` goes true→false; returns `null` on `sessionExpired`/timeout. |
| `AuthBlocRefreshInterceptor(authBloc, {required dio, timeout, onRefreshFailed, headerName, prefix, refreshOnStatusCodes})` | `AuthBloc` → `RefreshTokenInterceptor` | On a refresh-triggering status (401 by default) runs the strategy (AuthBloc's own singleflight), then retries the failed request via `dio` with the new token. |

## API

```dart
class AuthBlocIdentityProvider { AuthBlocIdentityProvider(AuthBloc); String? call(); }
class AuthBlocAuthInterceptor   extends AuthInterceptor { AuthBlocAuthInterceptor(AuthBloc, {…}); }
class AuthBlocRefreshStrategy   { AuthBlocRefreshStrategy(AuthBloc, {Duration timeout}); Future<String?> refresh(); }
class AuthBlocRefreshInterceptor extends RefreshTokenInterceptor { AuthBlocRefreshInterceptor(AuthBloc, {required Dio dio, …}); }
```

## Recipes

```dart
// Full wiring with logout on hard refresh failure.
final fetchBloc = FetchBloc(
  storageBloc: storageBloc, dio: dio,
  authIdentityProvider: AuthBlocIdentityProvider(authBloc).call,
);
fetchBloc.send(InitializeFetchEvent(
  config: const FetchConfig(baseUrl: 'https://api.example.com'),
  interceptors: [
    AuthBlocAuthInterceptor(authBloc),
    AuthBlocRefreshInterceptor(authBloc, dio: dio,
      onRefreshFailed: () async => authBloc.logout(force: true)),
  ],
));

// Identity-only (token added some other way), still isolate cache per user:
FetchBloc(storageBloc: storageBloc, authIdentityProvider: AuthBlocIdentityProvider(authBloc).call);
```

## Testing

Headless — fake `AuthProvider` + fake `StorageBloc` + a `http_mock_adapter` Dio.
Assert the identity flips across login/logout, the header is present, and a 401
triggers exactly one refresh (singleflight) then a successful retry.

```dart
final id = AuthBlocIdentityProvider(authBloc);
expect(id.call(), isNull);                 // unauthenticated
authBloc.loginWithEmail('a@b.c', 'pw'); await settle();
expect(id.call(), 'u1');                   // now scoped to the user
```

## Failure modes

- `AuthBlocRefreshStrategy.refresh()` returns **`null`** (never throws) on session
  expiry / timeout — matching `RefreshTokenInterceptor`'s contract: a null token
  means refresh-failed, the original 401 propagates, and `onRefreshFailed` fires.
- It seeds `sawRefreshing` from the current state so an already-in-flight refresh
  started by another caller is still observed (no missed edge).
- Identity is `null` when unauthenticated → `FetchBloc` uses its shared/unscoped
  cache; that's intended, not a fallback to another user's data.

## Anti-patterns

- ❌ Adding `AuthBlocAuthInterceptor` without `AuthBlocIdentityProvider` — the
  token is injected but cache/coalescing isn't user-scoped → cross-user leakage.
- ❌ Passing a different `Dio` to `AuthBlocRefreshInterceptor` than the one
  `FetchBloc` uses — the retry must go through the configured client.
- ❌ Re-implementing refresh singleflight here — it lives in `AuthBloc`; this
  package only observes it.
- ❌ Adding auth or network *domain* logic to this package — it is adapters only.

## Integrates with

- **juice_auth** — source of identity, token, and the refresh lifecycle.
- **juice_network** — consumer via `AuthIdentityProvider`, `AuthInterceptor`,
  `RefreshTokenInterceptor` seams.

## Invariants

- No bloc / state / events / groups — purely adapter classes.
- All three adapters read live `AuthBloc` state, so they reflect the latest token
  without re-wiring after a refresh.

## See also

`juice_auth` `doc/LLM.md` · `juice_network` `doc/LLM.md` · repo `AGENTS.md` ·
`ROADMAP.md` (glue-package architecture decision).
