# juice_auth_routing Specification

> **Status:** Implemented (shipping).
> **Package:** `juice_auth_routing` (glue)

## Overview

Glue between `juice_auth` (provider) and `juice_routing` (consumer): feeds
`AuthBloc` state into routing's guard system. Owns no domain — adapters + one
coordinator only. Naming follows the family convention `juice_<provider>_<consumer>`.

## Dependencies

`juice` + `juice_auth` + `juice_routing`. No third-party.

## Two mechanisms

### 1. Guard adapters (pull, on navigation)

`juice_routing` guards take plain callbacks; `AuthState` supplies the predicates.
Each adapter is a thin subclass:

| Adapter | Base guard | Wires |
|---------|-----------|-------|
| `AuthBlocAuthGuard(authBloc, {loginPath, restoreTimeout})` | `AuthGuard` | `isAuthenticated: () => authBloc.state.isAuthenticated`, after the wait below |
| `AuthBlocGuestGuard(authBloc, {redirectPath, restoreTimeout})` | `GuestGuard` | same predicate (inverted use), after the wait |
| `AuthBlocRoleGuard(authBloc, roleName, {restoreTimeout})` | `RoleGuard` | `hasRole: () => authBloc.state.hasRole(roleName)`, after the wait |

Evaluated by the routing pipeline on each navigation; the closures read live
`AuthBloc` state.

**Each adapter waits for the answer first.** `AuthState` starts as
`AuthStatus.unknown` and leaves it when the stored session has been restored
or found absent. Before it reads its predicate, an adapter awaits
`authBloc.waitFor((s) => s.status != AuthStatus.unknown, timeout:
restoreTimeout)` (`restoreTimeout` defaults to
`AuthBlocAuthGuard.defaultRestoreTimeout`, 10 seconds); a session already
known answers at once. `juice_routing` guards the initial path, so without
the wait a cold start read "not yet known" as "signed out" and started a
signed-in user on the login page (juice ISSUES #29). The wait's failures are
not caught: a timeout (`TimeoutException`) or a bloc that closes
(`StateError`) leaves the guard as a throw, which the pipeline reports as a
`GuardExceptionError` and refuses the navigation. No adapter falls back to
"signed out".

### 2. Reactive bridge (push, on auth change)

`AuthBlocRoutingBridge(authBloc, routingBloc, {loginPath, onAuthenticated})`
subscribes to `authBloc.stream` and drives `RoutingBloc.navigate`:

- authenticated → not (logout / `sessionExpired`) ⟶ `navigate(loginPath, replace: true)`
- → authenticated ⟶ `onAuthenticated(state)`

This covers the gap guards can't: a session ending *while on* a protected route.
Owns no state — a subscription with `start()` / `dispose()`.

## Direction

One-way: `AuthBloc` is the source of truth; the adapters/bridge read its state
and feed routing. `juice_auth` and `juice_routing` remain independent — this is
the only package that imports both.

## Out of scope (v1)

- The `returnTo` round-trip (returning to the original page after login) is left
  to the app via `onAuthenticated` — the return-path plumbing (query param vs
  state) is app-specific.

## Testing

Integration-style with a real `AuthBloc` (mock provider) + a real `RoutingBloc`
configured with guarded routes: guards allow/redirect/block through the actual
pipeline, and the bridge redirects to login on logout. All headless.

## Spec Version

| Version | Date | Status |
|---------|------|--------|
| 1.0 | 2026-05-28 | Implemented |
