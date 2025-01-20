# Changelog

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