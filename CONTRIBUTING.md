# Contributing to Juice

Thank you for considering contributing to Juice! This document outlines how you can contribute to the framework.

## Getting Started

1. Fork the repository and clone it locally
2. Run `flutter pub get` to install dependencies
3. Create a new branch for your changes
4. Make your changes
5. Run tests with `flutter test`
6. Create a pull request

## Development Process

### Setting Up Development Environment

1. Ensure you have Flutter installed and properly set up
2. Install an IDE with Flutter support (VS Code or Android Studio recommended)
3. Install the Dart and Flutter extensions for your IDE

### Framework Organization

The Juice framework's core components are organized as follows:

```
lib/
├── src/
│   ├── bloc/
│   │   ├── src/
│   │   │   ├── juice_bloc.dart         # Base bloc implementation
│   │   │   ├── bloc_state.dart         # State base class
│   │   │   ├── bloc_event.dart         # Event base classes
│   │   │   ├── bloc_scope.dart         # Lifecycle management
│   │   │   ├── usecase.dart            # Base use case classes
│   │   │   ├── juice_logger.dart       # Logging system
│   │   │   ├── core/
│   │   │   │   ├── event_dispatcher.dart
│   │   │   │   ├── status_emitter.dart
│   │   │   │   └── use_case_executor.dart
│   │   │   ├── lifecycle/
│   │   │   │   ├── bloc_lifecycle.dart  # Lifecycle enum
│   │   │   │   ├── bloc_lease.dart      # Lease system
│   │   │   │   ├── bloc_entry.dart      # Registration entry
│   │   │   │   └── feature_scope.dart   # Feature grouping
│   │   │   └── use_case_builders/
│   │   │       ├── use_case_builder.dart
│   │   │       ├── event_subscription.dart
│   │   │       └── relay_use_case_builder.dart
│   │   └── stream_status.dart          # Stream status types
│   └── ui/
│       └── src/
│           ├── stateless_juice_widget.dart
│           ├── juice_widget_state.dart
│           └── widget_support.dart

test/
├── bloc/
│   ├── bloc_scope_test.dart
│   ├── event_subscription_test.dart
│   ├── relay_use_case_builder_test.dart
│   └── resource_cleanup_test.dart
└── test_helpers.dart
```

### Recommended Application Structure

When building applications using Juice, I recommend organizing your code by features:

```
lib/
├── features/
│   ├── auth/
│   │   ├── bloc/
│   │   │   ├── auth_bloc.dart
│   │   │   ├── auth_state.dart
│   │   │   └── auth_events.dart
│   │   ├── use_cases/
│   │   │   ├── login_use_case.dart
│   │   │   └── logout_use_case.dart
│   │   └── ui/
│   │       └── login_widget.dart
│   └── profile/
│       ├── bloc/
│       │   ├── profile_bloc.dart
│       │   ├── profile_state.dart
│       │   └── profile_events.dart
│       ├── use_cases/
│       │   └── update_profile_use_case.dart
│       └── ui/
│           └── profile_editor.dart
├── shared/
│   └── widgets/
│       ├── buttons/
│       │   └── primary_button.dart
│       └── inputs/
│           └── styled_text_field.dart
└── core/
    └── utils/
        └── validators.dart
```

### Coding Standards

- Follow the [Effective Dart Guidelines](https://dart.dev/guides/language/effective-dart)
- Use `dart format` to format your code
- Ensure code passes `dart analyze` without warnings
- Add documentation comments for public APIs
- Write tests for new features

## Contributing to Juice Framework

Contributions to the core framework should focus on:

- Bug fixes
- Performance improvements
- Documentation improvements
- Test coverage
- Framework feature enhancements

## Making Changes

1. Check existing issues and pull requests
2. Create a new issue describing your proposed changes
3. Create a pull request referencing the issue

## Getting Help

- Use GitHub Discussions for questions and suggestions
- Check documentation at [GitHub Pages](https://kehmka.github.io/juice/)
- Create an issue for bugs or feature requests

## License

By contributing to Juice, you agree that your contributions will be licensed under its MIT license.