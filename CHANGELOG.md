# Changelog

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
