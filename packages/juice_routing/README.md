# juice_routing

Declarative, state-driven navigation for [Juice](https://pub.dev/packages/juice) applications with Navigator 2.0 integration, route guards, and deep linking.

[![pub package](https://img.shields.io/pub/v/juice_routing.svg)](https://pub.dev/packages/juice_routing)
[![License: MIT](https://img.shields.io/badge/license-MIT-purple.svg)](LICENSE)

## Features

- **Declarative Routes** - Define routes as configuration, not scattered `push()` calls
- **Route Guards** - Async guards for auth, permissions, onboarding with redirect loop protection
- **Navigation Atomicity** - Navigation either commits fully or not at all
- **Observable State** - Current route, stack, params, pending navigation all in `RoutingState`
- **Navigator 2.0** - Full integration with Flutter's declarative navigation API
- **Deep Linking** - Same path resolution for cold start, warm start, and in-app navigation

## Installation

```yaml
dependencies:
  juice_routing: ^1.0.0
```

## Quick Start

### 1. Define Your Routes

```dart
import 'package:juice_routing/juice_routing.dart';

final appRoutes = RoutingConfig(
  routes: [
    RouteConfig(
      path: '/',
      title: 'Home',
      builder: (ctx) => const HomeScreen(),
    ),
    RouteConfig(
      path: '/profile/:userId',
      title: 'Profile',
      builder: (ctx) => ProfileScreen(userId: ctx.params['userId']!),
      guards: [AuthGuard()],
    ),
    RouteConfig(
      path: '/settings',
      title: 'Settings',
      builder: (ctx) => const SettingsScreen(),
      guards: [AuthGuard()],
      children: [
        RouteConfig(
          path: 'account',
          builder: (ctx) => const AccountSettingsScreen(),
        ),
        RouteConfig(
          path: 'privacy',
          builder: (ctx) => const PrivacySettingsScreen(),
        ),
      ],
    ),
  ],
  notFoundRoute: RouteConfig(
    path: '/404',
    builder: (ctx) => const NotFoundScreen(),
  ),
);
```

### 2. Add Route Guards

Use the built-in guards or create your own:

```dart
// Built-in guards (callback-based, no auth dependency)
AuthGuard(isAuthenticated: () => authBloc.state.isLoggedIn)
GuestGuard(isAuthenticated: () => authBloc.state.isLoggedIn)
RoleGuard(hasRole: () => userBloc.state.isAdmin, roleName: 'admin')

// Or create custom guards
class OnboardingGuard extends RouteGuard {
  @override
  String get name => 'OnboardingGuard';

  @override
  Future<GuardResult> check(RouteContext context) async {
    if (userBloc.state.hasCompletedOnboarding) {
      return const GuardResult.allow();
    }
    return const GuardResult.redirect('/onboarding');
  }
}
```

### 3. Initialize and Use

```dart
import 'package:flutter/material.dart';
import 'package:juice/juice.dart';
import 'package:juice_routing/juice_routing.dart';

void main() {
  // Register RoutingBloc
  BlocScope.register<RoutingBloc>(
    () => RoutingBloc(),
    lifecycle: BlocLifecycle.permanent,
  );

  // Initialize with config
  final routingBloc = BlocScope.get<RoutingBloc>();
  routingBloc.send(InitializeRoutingEvent(config: appRoutes));

  runApp(MyApp(routingBloc: routingBloc));
}

class MyApp extends StatelessWidget {
  final RoutingBloc routingBloc;

  const MyApp({required this.routingBloc});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      routerDelegate: JuiceRouterDelegate(routingBloc: routingBloc),
      routeInformationParser: const JuiceRouteInformationParser(),
    );
  }
}
```

### 4. Navigate

```dart
final routingBloc = BlocScope.get<RoutingBloc>();

// Push a route
routingBloc.navigate('/profile/123');

// Replace current route
routingBloc.navigate('/home', replace: true);

// Pop
routingBloc.pop();

// Pop to root
routingBloc.popToRoot();

// Reset stack
routingBloc.resetStack('/login');
```

## Route Guards

Guards run automatically before navigation commits:

| Result | Behavior |
|--------|----------|
| `GuardResult.allow()` | Navigation proceeds |
| `GuardResult.redirect('/path')` | Redirects to another route |
| `GuardResult.block('reason')` | Blocks navigation, stays on current route |

Guards support:
- **Priority ordering** - Lower priority runs first
- **Async operations** - Token refresh, permission checks
- **Redirect loop protection** - Max 5 redirects before error

## Navigation Types

| Method | Guards Run? | Description |
|--------|-------------|-------------|
| `navigate(path)` | Yes | Push new route |
| `navigate(path, replace: true)` | Yes | Replace current route |
| `pop()` | No | Go back one route |
| `popToRoot()` | No | Clear stack to root |
| `popUntil(predicate)` | No | Pop until condition met |
| `resetStack(path)` | Yes | Clear and start fresh |

## Observable State

```dart
final state = routingBloc.state;

state.currentPath      // Current route path
state.stack            // Full navigation stack
state.stackDepth       // Number of routes in stack
state.canPop           // Whether pop is possible
state.isNavigating     // Guards currently running
state.history          // Navigation history
state.error            // Last navigation error
```

## Rebuild Groups

Subscribe to specific state changes:

| Group | Updates When |
|-------|--------------|
| `routing.stack` | Stack changes (push, pop, replace) |
| `routing.current` | Current route changes |
| `routing.pending` | Navigation in progress |
| `routing.history` | History entry added |
| `routing.error` | Navigation error occurred |

## Contract Guarantees

| Guarantee | Behavior |
|-----------|----------|
| **Atomicity** | Navigation commits fully or not at all |
| **Concurrency** | One pending navigation; new ones queue (latest wins) |
| **Redirect cap** | Max 5 redirects before `RedirectLoopError` |
| **Guard errors** | Exception becomes `GuardExceptionError`, navigation aborted |
| **Pop behavior** | Pop events bypass guards, execute immediately |

## Documentation

- [Getting Started](doc/getting-started.md) - Installation and setup
- [Route Configuration](doc/routes.md) - Defining routes and parameters
- [Route Guards](doc/guards.md) - Authentication, permissions, onboarding
- [Deep Linking](doc/deep-links.md) - Cold start and warm start handling
- [API Reference](doc/api.md) - Events, state, and configuration

## Example App

See the [example](example/) directory for a complete demo app showcasing:

- Route configuration with guards
- Navigation playground for testing all navigation types
- Aviator pattern for loose coupling
- History tracking and visualization

## License

MIT License - see [LICENSE](LICENSE) for details.
