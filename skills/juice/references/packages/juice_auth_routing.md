---
card_schema: "1.0"
package: juice_auth_routing
version: 0.1.0
requires:
  juice: ">=1.4.0"
  juice_auth: ">=0.2.1"
  juice_routing: ">=1.1.0"
updated: 2026-06-09
---

# juice_auth_routing — AI card

> **Glue** package: feeds `AuthBloc` (juice_auth) state into `RoutingBloc`
> (juice_routing) — AuthBloc-wired route guards plus a reactive bridge that
> redirects on auth changes. Adapters only — no new domain, no bloc, no state.
> Read repo `AGENTS.md` for the Juice mental model.

## Purpose

**Owns:** three `RouteGuard` subclasses pre-wired to `AuthBloc`, and one bridge
that watches auth transitions to redirect *between* navigations.
**Does NOT own:** auth logic (juice_auth) or the routing/guard engine
(juice_routing). It adds no events, state, or rebuild groups.

## Why both guards *and* a bridge

Guards are evaluated **on navigation** — they cannot evict a user whose session
ends *while sitting on* a protected route. The `AuthBlocRoutingBridge` closes that
gap by reacting to `AuthBloc` state changes. Use guards to gate entry; add the
bridge to handle mid-session logout/expiry.

## Install

```yaml
dependencies:
  juice_auth_routing: ^0.1.0
  juice_auth: ^0.2.1
  juice_routing: ^1.1.0
```

## Construct

Nothing to construct — attach the guards to routes and start the bridge once both
blocs exist:

```dart
final routing = RoutingBloc.withConfig(RoutingConfig(routes: [
  RouteConfig(path: '/profile', builder: (_) => ProfileScreen(),
    guards: [AuthBlocAuthGuard(authBloc)]),               // members only
  RouteConfig(path: '/admin', builder: (_) => AdminScreen(),
    guards: [AuthBlocRoleGuard(authBloc, 'admin')]),      // role-gated
  RouteConfig(path: '/login', builder: (_) => LoginScreen(),
    guards: [AuthBlocGuestGuard(authBloc)]),              // guests only
]));

// Evict on logout/expiry even while parked on a protected route:
final bridge = AuthBlocRoutingBridge(authBloc, routing,
  loginPath: '/login',
  onAuthenticated: (state) => routing.resetStack('/'),    // return after login
)..start();
// ... on teardown
bridge.dispose();
```

## What it wires

| Adapter | Wraps | Behavior |
|---|---|---|
| `AuthBlocAuthGuard(authBloc, {loginPath})` | `AuthGuard` | `isAuthenticated: () => authBloc.state.isAuthenticated`. Unauthenticated → `redirect(loginPath, returnTo: targetPath)`. |
| `AuthBlocGuestGuard(authBloc, {redirectPath})` | `GuestGuard` | Keeps *authenticated* users out of guest-only routes (login/signup) → redirect to `redirectPath` (default `/`). |
| `AuthBlocRoleGuard(authBloc, roleName)` | `RoleGuard` | `hasRole: () => authBloc.state.hasRole(roleName)`. Lacking the role → block. |
| `AuthBlocRoutingBridge(authBloc, routingBloc, {loginPath, onAuthenticated})` | (subscription) | Watches `authBloc.stream`: lose auth (→ unauthenticated/sessionExpired) → `navigate(loginPath, replace: true)`; gain auth → `onAuthenticated(state)`. Owns no state. |

## API

```dart
class AuthBlocAuthGuard  extends AuthGuard  { AuthBlocAuthGuard(AuthBloc, {String loginPath}); }
class AuthBlocGuestGuard extends GuestGuard { AuthBlocGuestGuard(AuthBloc, {String redirectPath}); }
class AuthBlocRoleGuard  extends RoleGuard  { AuthBlocRoleGuard(AuthBloc, String roleName); }
class AuthBlocRoutingBridge {
  AuthBlocRoutingBridge(AuthBloc, RoutingBloc, {String loginPath, void Function(AuthState)? onAuthenticated});
  void start();    // begin watching
  void dispose();  // cancel subscription
}
```

## Recipes

```dart
// Capture-and-return: AuthBlocAuthGuard puts the blocked target in returnTo.
RouteConfig(path: '/settings', builder: (_) => SettingsScreen(),
  guards: [AuthBlocAuthGuard(authBloc)]);          // → /login?returnTo=/settings

// After successful login, resume the captured destination:
final bridge = AuthBlocRoutingBridge(authBloc, routing,
  onAuthenticated: (_) => routing.resetStack(capturedReturnTo ?? '/'))..start();
```

## Testing

Headless — fake `AuthProvider` + fake `StorageBloc`; drive `AuthBloc`, assert the
routing stack reacts.

```dart
final bridge = AuthBlocRoutingBridge(authBloc, routing, loginPath: '/login')..start();
authBloc.loginWithEmail('a@b.c', 'pw'); await settle();
routing.navigate('/profile'); await settle();
expect(routing.state.currentPath, '/profile');
authBloc.logout(); await settle();
expect(routing.state.currentPath, '/login');       // bridge evicted on logout
```

## Failure modes

- The bridge fires on the authenticated→not-authenticated edge — covering both
  `unauthenticated` and `sessionExpired` (it reads `isAuthenticated`, which is
  false for both). It does **not** distinguish them; branch in `onAuthenticated`/
  the login screen if you need to.
- Guard *throws* propagate as `GuardExceptionError` from `juice_routing` — these
  adapters don't throw for expected denials (they redirect/block).
- The bridge must be `start()`-ed after both blocs exist and `dispose()`-d on
  teardown; it leaks a stream subscription otherwise.

## Anti-patterns

- ❌ Relying on guards alone for security on long-lived screens — add the bridge
  so a mid-session logout/expiry actually evicts the user.
- ❌ Re-implementing `isAuthenticated`/`hasRole` here — read `AuthState`.
- ❌ Adding routing or auth *domain* logic to this package — adapters only.
- ❌ Forgetting `bridge.dispose()` — dangling subscription on `AuthBloc.stream`.

## Integrates with

- **juice_auth** — source of `isAuthenticated`, `hasRole`, and auth transitions.
- **juice_routing** — consumer via `RouteGuard` and `RoutingBloc.navigate`.

## Invariants

- No bloc / state / events / groups — guard subclasses + one subscription owner.
- Guards evaluate at navigation time; the bridge covers between-navigation
  transitions. Together they're the full coverage.

## See also

`juice_auth` `doc/LLM.md` · `juice_routing` `doc/LLM.md` · `doc/SPEC.md` ·
repo `AGENTS.md` · `ROADMAP.md` (glue-package architecture decision).
