# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.1] - 2026-05-28

### Added
- Tests covering the README's previously-unverified refresh-scheduling claims:
  the past-window immediate-fire branch of `scheduleRefresh`, the auto-refresh
  `Timer` path (`scheduleRefresh` → `TokenExpiryEvent` → `RefreshTokenEvent`),
  and singleflight collapse of concurrent `RefreshTokenEvent`s into a single
  provider call.

### Changed
- `doc/SPEC.md` reconciled with the shipping implementation; added an
  Implementation Notes section documenting intentional divergences (code is the
  source of truth).

## [0.2.0] - 2026-04-18

### Changed

- Updated dependencies to `juice: ^1.4.0` and `juice_storage: ^1.2.0`
- Refreshed README examples to use the current `AuthBloc.withConfig(..., storageBloc: ...)` setup pattern

## [0.1.0] - 2026-02-14

### Added

- Initial release of juice_auth
- **`AuthBloc`** — primary bloc managing authentication lifecycle
- **`AuthState`** with `AuthStatus` enum (`unknown`, `unauthenticated`, `authenticated`, `sessionExpired`)
- **`AuthProvider`** interface — provider-agnostic contract for auth backends
- **`AuthCredentials`** hierarchy — `EmailCredentials`, `OAuthCredentials`, `ApiKeyCredentials`, `BiometricCredentials`
- **`LoginUseCase`** — authenticates via provider, persists tokens, emits state
- **`LogoutUseCase`** — atomic cleanup of tokens, storage, and session
- **`RefreshTokenUseCase`** — singleflight token refresh with `Completer`
- **`RestoreSessionUseCase`** — reads stored tokens on init, refreshes if valid
- **`AuthConfig`** — providers map, refresh buffer, rate limiting, storage prefix
- **`AuthError`** sealed hierarchy — `ProviderAuthError`, `RefreshFailedError`, `RateLimitedError`, etc.
- **Rebuild groups** — `auth:status`, `auth:user`, `auth:session`, `auth:error`
- **Aviators** — `loginSuccess`, `logoutComplete`, `sessionExpired`
- **Secure token persistence** via `juice_storage` `StorageBloc`
- **Login rate limiting** — configurable max attempts with cooldown
