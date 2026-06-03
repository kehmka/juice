# juice_auth_network

Integration glue between [`juice_auth`](https://pub.dev/packages/juice_auth) and [`juice_network`](https://pub.dev/packages/juice_network). Wires an `AuthBloc` into a `FetchBloc` so authenticated requests, 401 token refresh, and per-user cache isolation work without hand-written plumbing.

[![pub package](https://img.shields.io/pub/v/juice_auth_network.svg)](https://pub.dev/packages/juice_auth_network)
[![License: MIT](https://img.shields.io/badge/license-MIT-purple.svg)](LICENSE)

## Why

`juice_network`'s `FetchBloc` has three injection points for authentication, and `juice_auth`'s `AuthBloc` owns exactly that state. This package connects them:

| Injection point (`juice_network`) | Filled from (`juice_auth`) |
|---|---|
| `FetchBloc.authIdentityProvider` | the authenticated user's id — isolates cache/coalescing per user |
| `AuthInterceptor.tokenProvider` | `session.accessToken` — injects the current Bearer token |
| `RefreshTokenInterceptor.refreshToken` | `AuthBloc`'s singleflight refresh — handles 401s and retries |

Without this package you'd hand-wire those three callbacks and reimplement the
fire-and-forget → awaitable bridge for refresh. With it, it's three adapters.

## Installation

```yaml
dependencies:
  juice_auth: ^0.2.1
  juice_network: ^0.11.0
  juice_auth_network: ^0.1.0
```

## Usage

```dart
import 'package:dio/dio.dart';
import 'package:juice_auth/juice_auth.dart';
import 'package:juice_network/juice_network.dart';
import 'package:juice_auth_network/juice_auth_network.dart';

// Your already-configured AuthBloc.
final authBloc = BlocScope.get<AuthBloc>();

// One Dio instance, shared so the refresh interceptor can retry on it.
final dio = Dio();

final fetchBloc = FetchBloc(
  storageBloc: storageBloc,
  dio: dio,
  // Per-user cache isolation: cached responses never leak across users.
  authIdentityProvider: AuthBlocIdentityProvider(authBloc).call,
);

fetchBloc.send(InitializeFetchEvent(
  config: FetchConfig(baseUrl: 'https://api.example.com'),
  interceptors: [
    // Injects the current access token on every request.
    AuthBlocAuthInterceptor(authBloc),
    // On 401: runs AuthBloc's singleflight refresh, retries with the new token.
    AuthBlocRefreshInterceptor(authBloc, dio: dio),
  ],
));
```

That's the whole integration. Requests now carry the live token, expired tokens
refresh transparently, and the cache is scoped per authenticated user.

## What each adapter does

### `AuthBlocIdentityProvider`

Bridges `AuthBloc` to `FetchBloc.authIdentityProvider`. Returns the current
user id (or `null` when unauthenticated). Pass it as `provider.call`.

### `AuthBlocAuthInterceptor`

An `AuthInterceptor` whose `tokenProvider` reads `authBloc.state.session?.accessToken`
on every request — so the token is always current and never stale after a
refresh. Adds no header when there is no session. Accepts the usual
`AuthInterceptor` knobs (`headerName`, `prefix`, `skipAuth`).

### `AuthBlocRefreshInterceptor` / `AuthBlocRefreshStrategy`

`AuthBlocRefreshInterceptor` is a `RefreshTokenInterceptor` that, on a 401,
drives `AuthBloc.refreshToken()` and retries the failed request with the new
token. The bridge lives in `AuthBlocRefreshStrategy`: because
`AuthBloc.refreshToken()` is fire-and-forget, the strategy **watches the bloc's
state stream** and resolves with the new access token once the refresh
completes (`isRefreshing` → `false`), or `null` if the session expires. Pass the
same `Dio` instance you gave `FetchBloc` so the retried request goes through the
same transport.

## License

MIT License — see [LICENSE](LICENSE) for details.
