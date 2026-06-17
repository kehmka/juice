# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
