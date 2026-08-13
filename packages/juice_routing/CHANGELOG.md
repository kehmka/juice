# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.3.0] - 2026-08-12

### Changed

- Require `juice ^1.6.0`.
- Declare every routing event's concurrency policy explicitly.
- Keep navigation intentionally `concurrent` so requests arriving during an
  async guard can replace the depth-one queue and preserve latest-wins behavior.
- Run reset-stack and pop mutations `sequential`ly; initialization is
  `droppable`, while the shipped no-op visibility extension points remain
  intentionally `concurrent`.
- Update the example blocs to demonstrate explicit Juice 1.6 concurrency.

### Tests

- Replace timing-dependent guard overlap coverage with a gate that proves
  navigation remains latest-wins.
- Add gated coverage proving overlapping reset-stack commands run in FIFO order.

## [1.2.0] - 2026-07-16

### Fixed

- **Cold-start double push of the initial route**: Flutter's `Router` reports
  the platform's initial location (`setInitialRoutePath` → `setNewRoutePath`)
  on every startup, and the delegate forwarded it as a navigation — pushing a
  second copy of the path `InitializeRoutingEvent` had just seeded. Every app
  launched with a stack of two identical root pages (and a phantom back
  button). Platform reports of the *current* location now reconcile to a
  no-op; a report of a *different* location (a real deep link) still
  navigates.

### Added

- `NavigateEvent.fromPlatform` (default `false`): marks a navigation as a
  platform location report. Only platform-origin events dedupe against the
  current location — in-app `navigate()` calls keep intentional-push
  semantics, including re-pushing the current route with fresh `extra`.

## [1.1.0] - 2026-04-18

### Changed
- Updated core dependency to `juice: ^1.4.0`
- Refreshed README messaging and package guidance for the coordinated credibility release

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
