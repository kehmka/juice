# Recommended Project Structure

A well-organized project structure helps maintain code quality as your application grows. Here's the recommended structure for Juice applications, designed to scale from small to large projects.

## Basic Structure

```
lib/
├── main.dart                 # App entry point
├── config/                   # App configuration
│   ├── theme.dart           # App theme configuration
│   ├── routes.dart          # Route definitions
│   └── bloc_registry.dart   # Bloc registration
├── features/                # Feature modules
│   ├── auth/               # Authentication feature
│   ├── profile/            # Profile feature
│   └── settings/           # Settings feature
├── core/                    # Core application code
│   ├── services/           # Shared services
│   ├── models/             # Common data models
│   ├── widgets/            # Shared widgets
│   └── utils/              # Utility functions
└── generated/              # Generated files (localization, etc.)
```

## Feature Module Structure

Each feature should follow this structure (using auth as an example):

```
features/auth/
├── auth.dart               # Barrel file for the feature
├── auth_bloc.dart          # Feature's bloc
├── auth_state.dart         # State definition
├── auth_events.dart        # Event definitions
├── models/                 # Feature-specific models
│   ├── user.dart
│   └── credentials.dart
├── services/              # Feature-specific services
│   └── auth_service.dart
├── use_cases/            # Use case implementations
│   ├── login_use_case.dart
│   ├── logout_use_case.dart
│   └── register_use_case.dart
└── widgets/              # Feature UI components
    ├── login_form.dart
    ├── register_form.dart
    └── auth_page.dart
```

## Core Module Organization

The core module contains shared code used across features:

```
core/
├── services/              # Shared services
│   ├── api_service.dart   # Network client
│   ├── storage.dart       # Local storage
│   └── analytics.dart     # Analytics service
├── models/               # Common data models
│   ├── result.dart       # Result wrapper
│   └── error.dart        # Error models
├── widgets/              # Shared widgets
│   ├── buttons/
│   │   ├── primary_button.dart
│   │   └── secondary_button.dart
│   ├── inputs/
│   │   ├── text_input.dart
│   │   └── search_bar.dart
│   └── layouts/
│       ├── responsive_layout.dart
│       └── centered_layout.dart
└── utils/               # Utility functions
    ├── formatters.dart  # String/number formatting
    ├── validators.dart  # Input validation
    └── extensions/      # Extension methods
        ├── date_extensions.dart
        └── string_extensions.dart
```

## Feature Organization Best Practices

### Barrel Files
Each feature should have a barrel file exporting its public API:

```dart
// auth.dart
// State and Events
export 'auth_state.dart';
export 'auth_events.dart';
export 'auth_bloc.dart';
```

### Feature Boundaries
- Keep features self-contained
- Share code through core module
- Use barrel files to control public API
- Keep feature-specific code within feature directory

### This barrel file pattern:
- Provides a single import point for counter feature
- Makes imports cleaner in other files
- Helps manage feature boundaries
- Makes refactoring easier

### Things we should NOT export:

- Use cases (very rarely would you want to expore a usecase)
- Internal widgets 
- Internal models 
- Internal services - These should be accessed through the bloc

### The key principles are:

- Export only what other features need to interact with your feature
- Keep implementation details private to the feature
- Force interaction through the bloc's public interface
- Only expose models that are truly shared (if so, consider moving them out of the feature into a share folder)
- Expose pages needed for navigation

## Service Layer Organization

Services should be organized by scope:

```
services/
├── core/                # Core application services
│   ├── api/            # Network services
│   │   ├── api_client.dart
│   │   └── endpoints.dart
│   ├── storage/        # Storage services
│   │   ├── secure_storage.dart
│   │   └── preferences.dart
│   └── analytics/      # Analytics services
│       └── analytics_service.dart
└── feature/            # Feature-specific services can go here or in the feature folder
    ├── auth/
    │   └── auth_service.dart
    └── profile/
        └── profile_service.dart
```

## Widget Organization

Organize shared widgets by category:

```
widgets/
├── buttons/            # Button components
│   ├── primary_button.dart
│   └── secondary_button.dart
├── inputs/            # Input components
│   ├── text_input.dart
│   └── search_bar.dart
├── layouts/           # Layout components
│   ├── responsive_layout.dart
│   └── centered_layout.dart
└── feedback/          # Feedback components
    ├── loading_indicator.dart
    └── error_display.dart
```

## Dependency Management

### Configuration
```
config/
├── environment/       # Environment configuration
│   ├── dev.dart
│   ├── prod.dart
│   └── staging.dart
├── theme/            # Theme configuration
│   ├── colors.dart
│   └── typography.dart
└── bloc_registry.dart # Bloc registration
```

### Dependency Resolution
```dart
// bloc_registry.dart
class BlocRegistry {
  static void initialize() {
    // Core blocs
    BlocScope.registerFactory<AppBloc>(() => AppBloc());
    
    // Feature blocs
    BlocScope.registerFactory<AuthBloc>(() => AuthBloc(
      authService: resolve<AuthService>(),
      storage: resolve<StorageService>(),
    ));
    
    // More bloc registrations...
  }
}
```

## Testing Structure

Mirror your lib directory structure in test:

```
test/
├── features/          # Feature tests
│   └── auth/
│       ├── auth_bloc_test.dart
│       ├── use_cases/
│       │   └── login_use_case_test.dart
│       └── widgets/
│           └── login_form_test.dart
├── core/             # Core module tests
│   ├── services/
│   └── widgets/
└── integration/      # Integration tests
```

## Large Project Considerations

For larger projects, consider:

1. Module-based organization:
```
lib/
├── modules/
│   ├── authentication/    # Auth module
│   ├── messaging/         # Messaging module
│   └── payments/          # Payments module
└── shared/               # Shared code
```

2. Feature flags structure:
```
lib/
├── features/
│   └── experimental/     # Experimental features
└── config/
    └── feature_flags.dart
```

3. Multiple entry points:
```
lib/
├── main_prod.dart
├── main_dev.dart
└── main_