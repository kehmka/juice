# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
