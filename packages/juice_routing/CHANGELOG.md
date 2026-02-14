# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2026-02-14

### Added

- **Built-in guards**: `AuthGuard`, `RoleGuard`, `GuestGuard` — callback-based, decoupled from auth implementation
- **`maxHistorySize`** parameter on `RoutingConfig` (default 100) — oldest entries trimmed when limit exceeded
- **Redirect chain tracking** — `RedirectLoopError.redirectChain` now contains actual redirect paths for debugging

### Changed

- Guard pipeline extracted into shared `runGuardPipeline()` helper — eliminates ~60 lines of duplication between `NavigateUseCase` and `ResetStackUseCase`
- `ResetStackUseCase` now handles redirects internally (recursive) instead of dispatching new events
- Visibility use cases (`RouteVisibleUseCase`, `RouteHiddenUseCase`) are now clean no-ops with doc comments explaining their role as extension points

### Fixed

- `RedirectLoopError.redirectChain` was always `[]` — now populated with the actual path chain
- History could grow unbounded in long-lived apps — now capped by `maxHistorySize`

## [0.7.0] - 2026-01-26

### Added

- Initial release of juice_routing
- `RoutingBloc` for state-driven navigation management
- `RoutingState` with stack, history, pending navigation, and error tracking
- Path resolution with parameter extraction (`:param`) and wildcards (`*`)
- Route guard system with `GuardResult.allow()`, `redirect()`, and `block()`
- Redirect loop protection (max 5 redirects)
- Navigator 2.0 integration via `JuiceRouterDelegate` and `JuiceRouteInformationParser`
- Navigation events: `NavigateEvent`, `PopEvent`, `PopUntilEvent`, `PopToRootEvent`, `ResetStackEvent`
- Route visibility tracking with time-on-route measurement
- Rebuild groups for efficient UI updates
- Nested route support
- Route transitions (fade, slideRight, slideBottom, scale)
- Example app demonstrating all features
