# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.3.0] - 2026-11-10

### Fixed

- **A signed-in user's cold start landed on the login page.** `AuthBloc` is
  `AuthStatus.unknown` until a stored session has been restored, and the
  guards read that as "signed out". juice_routing 2.1.0 runs the guards on
  the initial path, so an app that built its routing before the restore
  finished started on `/login?returnTo=/` and stayed there.
  `AuthBlocAuthGuard`, `AuthBlocGuestGuard` and `AuthBlocRoleGuard` now
  WAIT until the session is known (`authBloc.waitFor`), then decide: the
  initial navigation stays pending — draw a splash from `state.pending` —
  and the login page is never shown to a signed-in user.

### Added

- **`restoreTimeout` on the three guards** (default
  `AuthBlocAuthGuard.defaultRestoreTimeout`, 10 seconds). A restore that
  has not answered by then makes the guard throw: juice_routing refuses
  the navigation with a `GuardExceptionError` carrying the
  `TimeoutException`. No guard falls back to "signed out".
- Each guard exposes its `authBloc`.

### Changed

- **Requires `juice ^2.1.0`** (`waitFor`), `juice_auth ^0.5.0` (a caret on
  0.4 does not admit 0.5) and `juice_routing ^2.1.0`, which guards the
  initial path — the wait exists for that — and shows a refused start on
  screen.

## [0.2.0] - 2026-10-14

### Changed

- **Requires `juice ^2.0.0`.** No API change in this package: the bump carries
  the core's breaking set (`doc/guides/upgrading-to-2.0.md`).
- Requires `juice_auth ^0.4.0` and `juice_routing ^2.0.0` (their 2.0-wave
  versions).

## [0.1.2] - 2026-09-15

### Changed
- Requires `juice: ^1.6.0` (was `^1.4.0`) — the constraint-only tail of
  ISSUES #22. This glue package registers no use cases; the floor now matches
  the family so a consumer cannot resolve a `juice` older than the one its
  dependencies assume. No API change.

## [0.1.1] - 2026-06-16

### Changed
- Allow `juice_storage` 2.0.0 (Hive CE migration). No API change.

## [0.1.0] - 2026-05-28

### Added

- Initial release — integration glue between `juice_auth` and `juice_routing`.
- **`AuthBlocAuthGuard`** — `AuthGuard` wired to `AuthBloc`; redirects
  unauthenticated users to login (with `returnTo`).
- **`AuthBlocGuestGuard`** — keeps authenticated users out of guest-only routes.
- **`AuthBlocRoleGuard`** — gates routes on `AuthState.hasRole`.
- **`AuthBlocRoutingBridge`** — watches `AuthBloc` and redirects to login when a
  session ends *while on* a protected route (logout / expiry), with an
  `onAuthenticated` hook for the login case.
