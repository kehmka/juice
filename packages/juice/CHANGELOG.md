# Changelog

## [1.2.0] - 2025-01-11

### New Features

#### ScopeLifecycleBloc - Reactive Scope Lifecycle Management
- Added `ScopeLifecycleBloc` as a permanent bloc that tracks `FeatureScope` lifecycle events
- Provides stream-based notifications for scope state changes:
  - `ScopeStartedNotification` - Emitted when a scope starts
  - `ScopeEndingNotification` - Emitted when scope cleanup begins (includes `CleanupBarrier`)
  - `ScopeEndedNotification` - Emitted when cleanup completes (includes success/timeout status)
- Enables reactive patterns for scope-aware features

#### CleanupBarrier - Deterministic Async Cleanup
- Added `CleanupBarrier` for coordinating async cleanup when scopes end
- Ensures in-flight operations complete or cancel before scope fully closes
- Features:
  - `barrier.add(Future)` - Register cleanup tasks
  - Configurable timeout (default: 30 seconds) prevents hung cleanup
  - `cleanupCompleted` flag indicates success vs timeout

```dart
// Subscribe to lifecycle notifications
lifecycleBloc.notifications.listen((notification) {
  if (notification is ScopeEndingNotification) {
    // Register cleanup work on the barrier
    notification.barrier.add(_cancelPendingRequests());
    notification.barrier.add(_saveUnsavedData());
  }
});
```

### Example App
- Added "Lifecycle Demo" showcasing ScopeLifecycleBloc capabilities:
  - Spawns parallel simulated async tasks with progress tracking
  - Demonstrates CleanupBarrier canceling in-flight tasks on scope end
  - Visual phase indicator (Idle → Active → Cleanup → Ended)
  - Color-coded event log showing all lifecycle notifications
  - Toggle for slow cleanup to test barrier timeout behavior

---

## [1.1.3] - 2025-01-10

### Fixes
- Events sent to a closed bloc are now gracefully ignored with a log message instead of throwing an error
- Fixed `JuiceWidgetState`, `JuiceWidgetState2`, `JuiceWidgetState3` to use `BlocScope` when `GlobalBlocResolver` is not configured
  - Previously threw `LateInitializationError` when using `BlocScope.register` pattern
  - Now properly acquires and releases bloc leases with lifecycle management
- Resolved pub.dev analyzer warnings:
  - Removed unnecessary imports in `bloc_scope.dart`, `event_subscription.dart`, `relay_use_case_builder.dart`, `bloc_tester.dart`
  - Updated constructors in `StatelessJuiceWidget` to use Dart 3 super parameters
- Fixed CI workflow: Updated Flutter to 3.27.1 for Dart SDK 3.5.4 compatibility

### Maintenance
- Added GitHub Sponsors funding link
- Code formatting pass across all packages

### Known Issues
- 9 analyzer hints remain for `State` type parameter naming (shadows Flutter's `State` class)
  - Will be renamed to `TState` in v2.0.0 as a breaking change

---

## [1.1.2] - 2025-01-04

### New Features

#### Inline Use Cases
- Added `InlineUseCaseBuilder` for simple, stateless operations
- Reduces boilerplate for operations that don't need dedicated class files
- Features:
  - `InlineContext<TBloc, TState>` with typed state access
  - `InlineEmitter` with clean `emit.update/waiting/failure/cancel` API
  - `Set<Object>` groups support (accepts `RebuildGroup`, enums, or strings)

```dart
() => InlineUseCaseBuilder<CounterBloc, CounterState, IncrementEvent>(
  typeOfEvent: IncrementEvent,
  handler: (ctx, event) async {
    ctx.emit.update(
      newState: ctx.state.copyWith(count: ctx.state.count + 1),
      groups: {CounterGroups.counter},
    );
  },
)
```

#### Type-Safe Rebuild Groups
- Added `RebuildGroup` class for compile-time safe rebuild groups
- Prevents typos, enables IDE autocomplete, supports refactoring
- Built-in `RebuildGroup.all` and `RebuildGroup.optOut`
- Extensions: `.toStringSet()` and `.toSet()` for conversion

```dart
abstract class CounterGroups {
  static const counter = RebuildGroup('counter');
  static const display = RebuildGroup('counter:display');
}

// Usage
emitUpdate(groupsToRebuild: {CounterGroups.counter}.toStringSet());
```

#### Retryable Use Cases
- Added `RetryableUseCaseBuilder` for automatic retry with configurable backoff
- Wraps any use case with retry logic, eliminating boilerplate
- Features:
  - Configurable `maxRetries` (default: 3)
  - Multiple backoff strategies: `FixedBackoff`, `ExponentialBackoff`, `LinearBackoff`
  - Custom retry conditions via `retryWhen` predicate
  - `onRetry` callback for logging/metrics
  - Respects `CancellableEvent` for early termination

```dart
() => RetryableUseCaseBuilder<MyBloc, MyState, FetchDataEvent>(
  typeOfEvent: FetchDataEvent,
  useCaseGenerator: () => FetchDataUseCase(),
  maxRetries: 3,
  backoff: ExponentialBackoff(
    initial: Duration(seconds: 1),
    maxDelay: Duration(seconds: 30),
    jitter: true,
  ),
)
```

### Deprecated
- `UpdateEvent.newState` parameter is now deprecated
  - State changes should go through dedicated use cases to maintain clean architecture
  - Will be removed in v2.0.0
  - Use `UpdateEvent` only for navigation triggers and status resets

### Documentation
- Added comprehensive dartdoc to `UpdateEvent` with usage examples
- Clarified correct vs incorrect usage patterns

### Tests
- Added 13 inline use case tests
- Added 10 RebuildGroup tests
- Added 15 RetryableUseCaseBuilder tests
- Total: 131 tests

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
