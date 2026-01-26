---
layout: default
title: Route Guards
nav_order: 4
---

# Route Guards

Route guards protect routes by running checks before navigation commits. They enable authentication, authorization, onboarding flows, and more.

## How Guards Work

When you navigate to a route:

1. Path is resolved to a `RouteConfig`
2. **Global guards** run in priority order
3. **Route guards** run in priority order
4. First non-allow result wins
5. If all guards allow, navigation commits

## Creating a Guard

Extend `RouteGuard` and implement `check()`:

```dart
class AuthGuard extends RouteGuard {
  @override
  String get name => 'AuthGuard';

  @override
  int get priority => 10;  // Lower runs first

  @override
  Future<GuardResult> check(RouteContext context) async {
    final authBloc = BlocScope.get<AuthBloc>();

    if (authBloc.state.isLoggedIn) {
      return const GuardResult.allow();
    }

    return GuardResult.redirect(
      '/login',
      returnTo: context.targetPath,
    );
  }
}
```

## Guard Results

### Allow

Navigation proceeds to the target route:

```dart
return const GuardResult.allow();
```

### Redirect

Navigation redirects to a different path:

```dart
return GuardResult.redirect('/login');

// With return path for after login
return GuardResult.redirect(
  '/login',
  returnTo: context.targetPath,
);
```

### Block

Navigation is blocked, user stays on current route:

```dart
return GuardResult.block('Insufficient permissions');
```

## RouteContext

Guards receive a `RouteContext` with navigation details:

```dart
class RouteContext {
  /// The path being navigated to
  final String targetPath;

  /// Extracted path parameters
  final Map<String, String> params;

  /// Query parameters
  final Map<String, String> query;

  /// Current routing state
  final RoutingState currentState;

  /// The target route configuration
  final RouteConfig targetRoute;
}
```

## Guard Priority

Guards run in priority order (lower number = runs first):

```dart
class LoggingGuard extends RouteGuard {
  @override
  int get priority => 1;  // Runs first
}

class AuthGuard extends RouteGuard {
  @override
  int get priority => 10;  // Runs after logging
}

class PermissionGuard extends RouteGuard {
  @override
  int get priority => 20;  // Runs after auth
}
```

Default priority is `0`.

## Common Guard Patterns

### Authentication Guard

```dart
class AuthGuard extends RouteGuard {
  @override
  String get name => 'AuthGuard';

  @override
  Future<GuardResult> check(RouteContext context) async {
    final authBloc = BlocScope.get<AuthBloc>();

    if (authBloc.state.isLoggedIn) {
      return const GuardResult.allow();
    }

    return GuardResult.redirect(
      '/login',
      returnTo: context.targetPath,
    );
  }
}
```

### Guest Guard (Redirect If Logged In)

```dart
class GuestGuard extends RouteGuard {
  @override
  String get name => 'GuestGuard';

  @override
  Future<GuardResult> check(RouteContext context) async {
    final authBloc = BlocScope.get<AuthBloc>();

    if (!authBloc.state.isLoggedIn) {
      return const GuardResult.allow();
    }

    // Already logged in, redirect to home
    return const GuardResult.redirect('/');
  }
}
```

### Permission Guard

```dart
class AdminGuard extends RouteGuard {
  @override
  String get name => 'AdminGuard';

  @override
  Future<GuardResult> check(RouteContext context) async {
    final authBloc = BlocScope.get<AuthBloc>();

    if (authBloc.state.isAdmin) {
      return const GuardResult.allow();
    }

    return GuardResult.block('Admin access required');
  }
}
```

### Onboarding Guard

```dart
class OnboardingGuard extends RouteGuard {
  @override
  String get name => 'OnboardingGuard';

  @override
  Future<GuardResult> check(RouteContext context) async {
    final userBloc = BlocScope.get<UserBloc>();

    if (userBloc.state.hasCompletedOnboarding) {
      return const GuardResult.allow();
    }

    return const GuardResult.redirect('/onboarding');
  }
}
```

### Async Token Refresh Guard

```dart
class TokenRefreshGuard extends RouteGuard {
  @override
  String get name => 'TokenRefreshGuard';

  @override
  int get priority => 5;  // Run early

  @override
  Future<GuardResult> check(RouteContext context) async {
    final authBloc = BlocScope.get<AuthBloc>();

    if (authBloc.state.tokenExpiresSoon) {
      try {
        await authBloc.refreshToken();
      } catch (e) {
        return const GuardResult.redirect('/login');
      }
    }

    return const GuardResult.allow();
  }
}
```

### Logging Guard

```dart
class LoggingGuard extends RouteGuard {
  @override
  String get name => 'LoggingGuard';

  @override
  int get priority => 1;  // Run first

  @override
  Future<GuardResult> check(RouteContext context) async {
    print('[Navigation] ${context.targetPath}');
    return const GuardResult.allow();
  }
}
```

## Applying Guards

### Route-Specific Guards

```dart
RouteConfig(
  path: '/admin',
  builder: (ctx) => const AdminPanel(),
  guards: [AuthGuard(), AdminGuard()],
)
```

### Global Guards

Run on every navigation:

```dart
final appRoutes = RoutingConfig(
  routes: [...],
  globalGuards: [
    LoggingGuard(),
    TokenRefreshGuard(),
  ],
);
```

### Combined Execution Order

1. Global guards (by priority)
2. Route guards (by priority)

## Redirect Loop Protection

Guards can redirect, and the redirected route may have its own guards. To prevent infinite loops, juice_routing caps redirect chains at 5:

```dart
// Guard A on /a redirects to /b
// Guard B on /b redirects to /a
// This would loop forever without protection

// After 5 redirects, navigation fails with RedirectLoopError
```

Configure the limit:

```dart
final appRoutes = RoutingConfig(
  routes: [...],
  maxRedirects: 10,  // Default is 5
);
```

## Error Handling

### Guard Exception

If a guard throws an exception:

```dart
@override
Future<GuardResult> check(RouteContext context) async {
  throw Exception('Network error');  // Oops!
}
```

Navigation is aborted and `GuardExceptionError` is set in state:

```dart
if (routingBloc.state.error is GuardExceptionError) {
  final error = routingBloc.state.error as GuardExceptionError;
  print('Guard ${error.guard.name} failed: ${error.exception}');
}
```

### Guard Blocked

When a guard blocks navigation:

```dart
if (routingBloc.state.error is GuardBlockedError) {
  final error = routingBloc.state.error as GuardBlockedError;
  print('Navigation blocked: ${error.reason}');
}
```

## When Guards DON'T Run

Guards only run for forward navigation. These operations bypass guards:

| Operation | Guards Run? |
|-----------|-------------|
| `navigate(path)` | Yes |
| `navigate(path, replace: true)` | Yes |
| `resetStack(path)` | Yes |
| `pop()` | **No** |
| `popToRoot()` | **No** |
| `popUntil(predicate)` | **No** |

This is by design: users should always be able to go back.

## Testing Guards

```dart
test('AuthGuard redirects when not logged in', () async {
  // Setup
  final authBloc = MockAuthBloc();
  when(authBloc.state).thenReturn(AuthState(isLoggedIn: false));
  BlocScope.register<AuthBloc>(() => authBloc);

  final guard = AuthGuard();
  final context = RouteContext(
    targetPath: '/profile',
    params: {},
    query: {},
    currentState: RoutingState.initial,
    targetRoute: profileRoute,
  );

  // Act
  final result = await guard.check(context);

  // Assert
  expect(result, isA<RedirectResult>());
  expect((result as RedirectResult).path, '/login');
});
```
