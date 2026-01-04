# Changelog

## [1.1.2] - 2025-01-04

### Deprecated
- `UpdateEvent.newState` parameter is now deprecated
  - State changes should go through dedicated use cases to maintain clean architecture
  - Will be removed in v2.0.0
  - Use `UpdateEvent` only for navigation triggers and status resets

### Documentation
- Added comprehensive dartdoc to `UpdateEvent` with usage examples
- Clarified correct vs incorrect usage patterns

---

## [1.1.1] - 2025-01-04

### Documentation
- Added comprehensive library-level dartdoc to `juice.dart`
- Improved pub.dev documentation score

### Fixes
- Suppressed `must_be_immutable` analyzer warnings (intentional design for late-initialized bloc fields)

---

## [1.1.0] - 2025-01-04

### New Features

#### BlocScope Lifecycle Management
- Introduced `BlocScope` for semantic bloc lifecycle control
- Added three lifecycle options:
  - `BlocLifecycle.permanent` - App-level blocs that live for entire app lifetime
  - `BlocLifecycle.feature` - Blocs scoped to a feature, disposed together via `FeatureScope`
  - `BlocLifecycle.leased` - Widget-level blocs with automatic reference-counted disposal
- Added `BlocLease<T>` for safe bloc access with automatic cleanup
- Added `BlocScope.diagnostics<T>()` for debugging bloc state
- Added `BlocScope.debugDump()` for development diagnostics

#### Cross-Bloc Communication
- Added `EventSubscription` for listening to events from one bloc and forwarding to another
- Added `StateRelay` for simple state-to-event transformation between blocs
- Added `StatusRelay` for full StreamStatus access when reacting to state changes
- Added `when` predicate filtering for both event subscriptions and relays

### Deprecated
- `RelayUseCaseBuilder` is now deprecated in favor of `StateRelay` and `StatusRelay`
  - `StateRelay` - Use when you only need to react to state changes (most common)
  - `StatusRelay` - Use when you need to handle waiting/error states
  - Will be removed in v2.0.0

### Bug Fixes
- Fixed race condition in `EventSubscription` initialization when `close()` called before microtask executes
- Fixed race condition in `RelayUseCaseBuilder` initialization
- Fixed unsafe dynamic cast in `UseCaseExecutor` - replaced with type-safe `setBloc()` method
- Fixed forced non-null access in `widget_support.dart` with safe null-coalescing
- Fixed inconsistent default groups in `StatelessJuiceWidget2` (now uses `{"*"}` like other variants)

### Improvements
- Added bloc type context to relay error messages for better debugging
- Added warning log when `EventDispatcher` uses unhandled event fallback
- Simplified verbose error throwing patterns in `JuiceAsyncBuilder` with helper getters
- Removed ambiguous `_Disposable` interface from `JuiceBloc`, documented `dispose()` method
- Added event type to state emission logs for improved observability

### Tests
- Added comprehensive test suite for `BlocScope` lifecycle management (20 tests)
- Added `EventSubscription` tests covering transformation, filtering, and race conditions (10 tests)
- Added `RelayUseCaseBuilder` tests covering relay, error handling, and multi-relay scenarios (10 tests)
- Added `StateRelay` and `StatusRelay` tests (13 tests)
- Added resource cleanup tests for bloc close, stream cleanup, and lease disposal (9 tests)
- Total: 62 new tests, 93 tests overall

### Documentation
- Updated README to use `BlocScope` instead of `GlobalBlocResolver`
- Added comprehensive documentation for lifecycle management
- Added cross-bloc communication examples
- Updated Best Practices with lifecycle and communication guidelines

### Migration Guide
`GlobalBlocResolver` is still available for backwards compatibility, but `BlocScope` is now the recommended approach:

```dart
// Before (still works)
GlobalBlocResolver().resolver = BlocResolver();

// After (recommended)
BlocScope.register<MyBloc>(
  () => MyBloc(),
  lifecycle: BlocLifecycle.permanent,
);
```

---

## [1.0.4] - 2025-02-08

### Tests
- Created new `StatelessJuiceWidget` tests to verify rebuild behavior across groups.
- Added BLoC lifecycle tests ensuring proper close and cleanup.
- Increased test coverage for error-handling and wildcard group rebuild logic.

### Maintenance
- Version bump in `pubspec.yaml` to `1.0.4`.

## [1.0.3] - 2025-02-07

### Documentation
- Updated `README.md` with various improvements.
- Improved package documentation for better clarity.
- Improved dart doc processing

### Maintenance
- Version bump in `pubspec.yaml` to `1.0.3`.

## [1.0.2] - 2025-01-30

### Documentation
- Updated `README.md` with various improvements.
- Improved package documentation for better clarity.
- Removed misleading `copyWith` mention in comments within `bloc_state.dart`.
- Properly escaped angle brackets in dartdoc comments

### Community & Support
- Added initial setup for `FUNDING.yaml` to support sponsorship options.

### Maintenance
- Version bump in `pubspec.yaml` to `1.0.2`.

## [1.0.1] - 2025-01-23

### Enhancements
- Added `StatusChecks` extension for `StreamStatus`:
  - Includes methods for type-checking (`isUpdatingFor`, `isWaitingFor`, etc.).
  - Added safe casting methods (`tryCastToUpdating`, `tryCastToWaiting`, etc.).
  - Introduced a `match` method for pattern-matching on `StreamStatus` types.
  - Simplified handling of `StreamStatus` across widgets and logic.

### Developer Experience
- Improved type safety and reduced boilerplate for handling transient states.
- Enhanced readability and maintainability of `StreamStatus` usage.

## [1.0.0] - 2025-01-16

### Core Features
- Introduced JuiceBloc with use case-driven state management
- Implemented StreamStatus<T> for type-safe state transitions (Updating/Waiting/Failure)
- Added group-based widget rebuilding system for performance optimization
- Created StatelessJuiceWidget for reactive UI updates

### Use Case System
- Introduced BlocUseCase for structured business logic
- Added StatefulUseCaseBuilder for singleton use cases
- Implemented RelayUseCaseBuilder for bloc-to-bloc communication
- Added UpdateUseCase for quick state updates

### Navigation
- Implemented Aviator system for declarative navigation
- Added DeepLinkAviator for handling deep linking
- Created base AviatorBase class for custom navigation handlers

### Dependency Resolution
- Added BlocDependencyResolver interface
- Implemented GlobalBlocResolver for centralized bloc management
- Created CompositeResolver for flexible dependency injection

### Widgets
- StatelessJuiceWidget and JuiceWidgetState for single bloc binding
- StatelessJuiceWidget2 and StatelessJuiceWidget3 for multiple bloc bindings
- Added JuiceAsyncBuilder for stream handling

### Logging & Error Handling
- Implemented JuiceLogger interface
- Added DefaultJuiceLogger with configurable options
- Created structured error handling system

### Developer Experience
- Added comprehensive code documentation
- Implemented type-safe APIs throughout
- Created builder patterns for common operations

## Initial Contributors
- Kevin Ehmka

Note: This is the first stable release of Juice, a state management solution designed to provide a clean architecture plus bloc approach to Flutter applications.
