# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.3.0] - 2026-11-10

### Changed

- **Requires `juice ^2.1.0`, `juice_auth ^0.5.0` and
  `juice_network ^0.15.0`.**
- **`AuthBlocRefreshStrategy.refresh` is one
  `sendForResult(RefreshTokenEvent())`.** It no longer watches the bloc's
  stream for the `isRefreshing` edge; a refresh requested while one runs
  joins it. It still answers null on every failure — no refresh token,
  the provider refused, the bloc closed, the timeout — which is the
  interceptor's contract, and now logs what the wait threw at error level:
  a timeout or a close was otherwise recorded nowhere.
- Doc examples build `FetchBloc` with `AuthBlocIdentityProvider`, which
  juice_network 0.15.0 requires beside an `AuthInterceptor`.

### Fixed

- **The refresh strategy waited the full 30 seconds when the refresh
  failed.** A refresh with no refresh token fails before `isRefreshing`
  is ever set, so the edge the strategy waited on never came. It now
  finishes as soon as the refresh fails.

## [0.2.0] - 2026-10-14

### Changed

- **Requires `juice ^2.0.0`.** No API change in this package: the bump carries
  the core's breaking set (`doc/guides/upgrading-to-2.0.md`).
- Requires `juice_auth ^0.4.0` and `juice_network ^0.14.0` (their 2.0-wave
  versions).

## [0.1.3] - 2026-09-15

### Changed
- Requires `juice: ^1.6.0` (was `^1.4.0`) — the constraint-only tail of
  ISSUES #22. This glue package registers no use cases; the floor now matches
  the family so a consumer cannot resolve a `juice` older than the one its
  dependencies assume. No API change.

## [0.1.2] - 2026-06-16

### Changed
- Allow `juice_storage` 2.0.0 (Hive CE migration). No API change.

## [0.1.1] - 2026-06-09

### Fixed

- Widen the `juice_network` constraint from `^0.11.0` to `^0.12.0` — the old pin
  excluded the published `juice_network` 0.12.0, so released consumers couldn't
  resolve the two together. Verified against 0.12.0 (analyze clean, 8 tests).

## [0.1.0] - 2026-05-28

### Added

- Initial release — integration glue between `juice_auth` and `juice_network`.
- **`AuthBlocIdentityProvider`** — feeds `FetchBloc.authIdentityProvider` from
  `AuthBloc` for per-user cache/coalescing isolation.
- **`AuthBlocAuthInterceptor`** — an `AuthInterceptor` that injects the current
  access token from `AuthBloc` state.
- **`AuthBlocRefreshInterceptor`** — a `RefreshTokenInterceptor` that drives
  `AuthBloc`'s singleflight refresh on 401 and retries with the new token.
- **`AuthBlocRefreshStrategy`** — the stream-watching bridge that triggers
  `AuthBloc.refreshToken()` and resolves when the refresh completes (or fails
  with session expiry).
- Example app demonstrating login, token injection, and refresh, built with
  Juice primitives only (AuthBloc, FetchBloc, a ProfileBloc feature bloc, and
  StatelessJuiceWidget).
