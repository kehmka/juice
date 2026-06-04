# juice_auth_routing

Integration glue between [`juice_auth`](https://pub.dev/packages/juice_auth) and
[`juice_routing`](https://pub.dev/packages/juice_routing). Feeds `AuthBloc` state
into routing's guard system, two ways: **guards** (checked on navigation) and a
**reactive bridge** (redirects when auth changes mid-session).

[![pub package](https://img.shields.io/pub/v/juice_auth_routing.svg)](https://pub.dev/packages/juice_auth_routing)
[![License: MIT](https://img.shields.io/badge/license-MIT-purple.svg)](LICENSE)

## Why

`juice_routing`'s guards are callback-decoupled, and `AuthState` supplies exactly
the predicates they need (`isAuthenticated`, `hasRole`). This package pre-wires
them — and adds the piece guards alone can't do: evicting a user whose session
ends while they're sitting on a protected route.

## Install

```yaml
dependencies:
  juice_auth: ^0.2.1
  juice_routing: ^1.1.0
  juice_auth_routing: ^0.1.0
```

## Guards (checked on navigation)

```dart
final routing = RoutingBloc.withConfig(RoutingConfig(routes: [
  RouteConfig(path: '/profile', builder: ...,
    guards: [AuthBlocAuthGuard(authBloc)]),            // require auth → /login
  RouteConfig(path: '/login', builder: ...,
    guards: [AuthBlocGuestGuard(authBloc)]),           // bounce if logged in
  RouteConfig(path: '/admin', builder: ...,
    guards: [AuthBlocRoleGuard(authBloc, 'admin')]),   // require a role
]));
```

| Guard | Behavior |
|-------|----------|
| `AuthBlocAuthGuard` | unauthenticated → redirect to `loginPath` (carries `returnTo`) |
| `AuthBlocGuestGuard` | authenticated → redirect to `redirectPath` (keeps you out of login/signup) |
| `AuthBlocRoleGuard` | missing role → block |

## Reactive bridge (auth changes mid-session)

Guards run *on navigation* — they don't evict a user who logs out (or whose
session expires) while already on a protected screen. `AuthBlocRoutingBridge`
watches `AuthBloc` and reacts:

```dart
final bridge = AuthBlocRoutingBridge(
  authBloc,
  routingBloc,
  loginPath: '/login',
  onAuthenticated: (state) => routingBloc.navigate('/'), // optional
)..start();

// ... on teardown
bridge.dispose();
```

- **Loses auth** (logout *or* `sessionExpired`) → `navigate(loginPath, replace: true)`.
- **Gains auth** → `onAuthenticated(state)`.

It owns no state — just a subscription.

## License

MIT License — see [LICENSE](LICENSE).
