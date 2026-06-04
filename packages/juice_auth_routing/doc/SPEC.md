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
| `AuthBlocAuthGuard(authBloc, {loginPath})` | `AuthGuard` | `isAuthenticated: () => authBloc.state.isAuthenticated` |
| `AuthBlocGuestGuard(authBloc, {redirectPath})` | `GuestGuard` | same predicate (inverted use) |
| `AuthBlocRoleGuard(authBloc, roleName)` | `RoleGuard` | `hasRole: () => authBloc.state.hasRole(roleName)` |

Evaluated by the routing pipeline on each navigation; the closures read live
`AuthBloc` state.

### 2. Reactive bridge (push, on auth change)

`AuthBlocRoutingBridge(authBloc, routingBloc, {loginPath, onAuthenticated})`
subscribes to `authBloc.stream` and drives `RoutingBloc.navigate`:

- authenticated → not (logout / `sessionExpired`) ⟶ `navigate(loginPath, replace: true)`
- → authenticated ⟶ `onAuthenticated(state)`

This covers the gap guards can't: a session ending *while on* a protected route.
Owns no state — a subscription with `start()` / `dispose()`. (Same stream-watch
shape as `juice_auth_network`'s refresh strategy.)

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
