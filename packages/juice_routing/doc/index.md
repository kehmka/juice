---
layout: default
title: Home
nav_order: 1
---

# juice_routing

Declarative, state-driven navigation for [Juice](https://pub.dev/packages/juice) applications with Navigator 2.0 integration, route guards, deep linking, and automatic scope management.

{: .highlight }
juice_routing makes navigation atomic, observable, and testable—routes become bloc state, guards run as use cases, and deep links flow through the same event system as everything else.

## Key Features

| Feature | Description |
|---------|-------------|
| **Declarative Routes** | Define routes as configuration, not scattered `push()` calls |
| **Route Guards** | Async guards for auth, permissions, onboarding with redirect loop protection |
| **Navigation Atomicity** | Navigation either commits fully or not at all—no partial states |
| **Observable State** | Current route, stack, params, pending navigation all in `RoutingState` |
| **Scope Integration** | Navigate away → feature scope ends → automatic cleanup |
| **Testable** | Unit test navigation logic without widget tests |

## Installation

```yaml
dependencies:
  juice_routing: ^0.1.0
```

## Quick Example

```dart
// Configure routes
final config = RoutingConfig(
  routes: [
    RouteConfig(
      path: '/',
      builder: (ctx) => HomeScreen(),
    ),
    RouteConfig(
      path: '/profile/:userId',
      builder: (ctx) => ProfileScreen(userId: ctx.params['userId']!),
      guards: [AuthGuard(isAuthenticated: () => authBloc.state.isLoggedIn)],
    ),
  ],
);

// Initialize
BlocScope.register<RoutingBloc>(
  () => RoutingBloc(),
  lifecycle: BlocLifecycle.permanent,
);

final routingBloc = BlocScope.get<RoutingBloc>();
routingBloc.send(InitializeRoutingEvent(config: config));

// Navigate
routingBloc.send(NavigateEvent(path: '/profile/123'));
```

## Why juice_routing?

### Problem: Imperative Navigation

In Flutter, navigation is typically imperative:

```dart
// Scattered throughout your codebase
Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileScreen()));

// Guard logic duplicated everywhere
if (authService.isLoggedIn) {
  Navigator.pushNamed(context, '/settings');
} else {
  Navigator.pushNamed(context, '/login');
}
```

This leads to:
- Guards copy-pasted into every navigation call
- Deep links handled separately from in-app navigation
- No visibility into "where am I?" or navigation history
- Untestable without full widget tests

### Solution: Declarative Navigation

juice_routing makes navigation state-driven:

```dart
// Define guard once
class AuthGuard extends RouteGuard {
  @override
  Future<GuardResult> check(RouteContext context) async {
    if (isAuthenticated()) return GuardResult.allow();
    return GuardResult.redirect('/login', returnTo: context.targetPath);
  }
}

// Apply to routes
RouteConfig(
  path: '/settings',
  guards: [AuthGuard()],
  builder: (ctx) => SettingsScreen(),
)

// Navigate normally—guard runs automatically
routingBloc.send(NavigateEvent(path: '/settings'));
```

Guards run automatically. Deep links resolve through the same path. State updates are observable.

## Contract Guarantees

| Guarantee | Behavior |
|-----------|----------|
| **Atomicity** | Navigation either commits fully or not at all |
| **Concurrency** | One pending navigation; new ones queue (latest wins) |
| **Redirect cap** | Max 5 redirects before `RedirectLoopError` |
| **Guard errors** | Exception → `GuardExceptionError`, navigation aborted |
| **Pop behavior** | Pop events bypass guards, execute immediately |

## Documentation

- [Getting Started](getting-started.html) - Installation and setup
- [Route Configuration](routes.html) - Defining routes and parameters
- [Route Guards](guards.html) - Authentication, permissions, onboarding
- [Deep Linking](deep-links.html) - Cold start and warm start handling
- [API Reference](api.html) - Events, state, and configuration

## Part of the Juice Framework

juice_routing is a companion package for [Juice](https://pub.dev/packages/juice), the reactive architecture framework for Flutter. It follows Juice patterns:

- **BlocScope** for lifecycle management
- **Events** for triggering navigation
- **Use Cases** for guard logic
- **Rebuild Groups** for efficient UI updates
- **FeatureScope** integration for automatic cleanup
