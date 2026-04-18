# Juice Framework Development Guidelines

## Build & Test Commands
```bash
# Run all tests
flutter test

# Run a specific test file
flutter test example/test/counter_bloc_test.dart

# Run with coverage
flutter test --coverage

# Run formatter
dart format lib/

# Run linter
flutter analyze
```

## Code Style Guidelines
- **Imports**: Use package imports (`import 'package:juice/juice.dart'`)
- **Classes**: Use `JuiceBloc<TState>` for bloc classes, with immutable state via `copyWith`
- **Types**: Always specify generic types (e.g., `UseCaseBuilder<TEvent>`)
- **Naming**:
  - Blocs: `FeatureBloc`
  - States: `FeatureState`
  - Events: `ActionVerb` + `Event` (e.g., `IncrementEvent`)
  - Use cases: `ActionVerb` + `UseCase` (e.g., `IncrementUseCase`)
- **Groups**: Define rebuild groups with intent-revealing names
- **Error Handling**: Use `emitFailure` in use cases for errors
- **Resource Cleanup**: Always implement `close()` method properly
- **Comments**: Document public APIs with /// doc comments
- **Bloc Structure**: Follow the initialization pattern with initial state, use cases, and aviators