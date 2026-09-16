# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
