---
layout: default
title: Getting Started
nav_order: 2
---

# Getting Started

This guide walks you through setting up juice_routing in your Flutter application.

## Prerequisites

- Flutter 3.0+
- [juice](https://pub.dev/packages/juice) package

## Installation

Add the dependency to your `pubspec.yaml`:

```yaml
dependencies:
  juice: ^1.2.0
  juice_routing: ^0.1.0
```

Then run:

```bash
flutter pub get
```

## Setup

### 1. Define Your Routes

Create a route configuration file:

```dart
// lib/routes.dart
import 'package:juice_routing/juice_routing.dart';
import 'screens/home_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/login_screen.dart';
import 'screens/not_found_screen.dart';

final appRoutes = RoutingConfig(
  routes: [
    RouteConfig(
      path: '/',
      title: 'Home',
      builder: (ctx) => const HomeScreen(),
    ),
    RouteConfig(
      path: '/login',
      title: 'Login',
      builder: (ctx) => const LoginScreen(),
    ),
    RouteConfig(
      path: '/profile/:userId',
      title: 'Profile',
      builder: (ctx) => ProfileScreen(
        userId: ctx.params['userId']!,
      ),
    ),
  ],
  notFoundRoute: RouteConfig(
    path: '/404',
    title: 'Not Found',
    builder: (ctx) => const NotFoundScreen(),
  ),
  initialPath: '/',
);
```

### 2. Register and Initialize RoutingBloc

In your main.dart:

```dart
import 'package:flutter/material.dart';
import 'package:juice/juice.dart';
import 'package:juice_routing/juice_routing.dart';
import 'routes.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late final RoutingBloc _routingBloc;
  late final JuiceRouterDelegate _routerDelegate;

  @override
  void initState() {
    super.initState();

    // Register RoutingBloc globally
    BlocScope.register<RoutingBloc>(
      () => RoutingBloc(),
      lifecycle: BlocLifecycle.permanent,
    );

    // Get instance and initialize
    _routingBloc = BlocScope.get<RoutingBloc>();
    _routingBloc.send(InitializeRoutingEvent(config: appRoutes));

    // Create router delegate
    _routerDelegate = JuiceRouterDelegate(routingBloc: _routingBloc);
  }

  @override
  void dispose() {
    _routerDelegate.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'My App',
      routerDelegate: _routerDelegate,
      routeInformationParser: const JuiceRouteInformationParser(),
    );
  }
}
```

### 3. Navigate in Your App

Access the RoutingBloc from anywhere:

```dart
class HomeScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final routingBloc = BlocScope.get<RoutingBloc>();

    return Scaffold(
      appBar: AppBar(title: const Text('Home')),
      body: Center(
        child: ElevatedButton(
          onPressed: () => routingBloc.navigate('/profile/123'),
          child: const Text('View Profile'),
        ),
      ),
    );
  }
}
```

## Navigation Methods

### Push a New Route

```dart
routingBloc.navigate('/profile/123');

// With extra data
routingBloc.navigate('/profile/123', extra: {'source': 'home'});
```

### Replace Current Route

```dart
routingBloc.navigate('/dashboard', replace: true);
```

### Pop (Go Back)

```dart
routingBloc.pop();

// With result
routingBloc.pop(result: selectedItem);
```

### Pop to Root

```dart
routingBloc.popToRoot();
```

### Pop Until Condition

```dart
routingBloc.popUntil((entry) => entry.path == '/');
```

### Reset Stack

```dart
routingBloc.resetStack('/login');
```

## Reading Navigation State

```dart
final state = routingBloc.state;

// Current location
print('Path: ${state.currentPath}');
print('Stack depth: ${state.stackDepth}');
print('Can pop: ${state.canPop}');

// Check if navigating
if (state.isNavigating) {
  print('Guards are running...');
}

// Check for errors
if (state.error != null) {
  print('Error: ${state.error}');
}
```

## Reacting to Navigation Changes

Use StreamBuilder or JuiceAsyncBuilder:

```dart
StreamBuilder(
  stream: routingBloc.stream,
  builder: (context, snapshot) {
    final path = routingBloc.state.currentPath;
    return Text('Current: $path');
  },
)
```

## Next Steps

- Learn about [Route Configuration](routes.html) for parameters, nested routes, and transitions
- Add authentication with [Route Guards](guards.html)
- Handle [Deep Links](deep-links.html) for web and mobile
- See the [API Reference](api.html) for all available options
