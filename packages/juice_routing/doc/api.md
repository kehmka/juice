---
layout: default
title: API Reference
nav_order: 6
---

# API Reference

Complete reference for juice_routing classes, events, and configuration.

## RoutingBloc

The main bloc for navigation management.

### Constructor

```dart
RoutingBloc()
```

### Factory Constructor

```dart
RoutingBloc.withConfig(RoutingConfig config, {String? initialPath})
```

Creates and initializes a RoutingBloc in one step.

### Properties

| Property | Type | Description |
|----------|------|-------------|
| `state` | `RoutingState` | Current routing state |
| `stream` | `Stream<StreamStatus<RoutingState>>` | State change stream |
| `config` | `RoutingConfig` | Route configuration (after init) |
| `pathResolver` | `PathResolver` | Path resolver (after init) |

### Methods

| Method | Description |
|--------|-------------|
| `navigate(path, {extra, replace})` | Navigate to a path |
| `pop({result})` | Pop current route |
| `popToRoot()` | Pop all routes except root |
| `popUntil(predicate)` | Pop until condition is met |
| `resetStack(path, {extra})` | Clear stack and navigate |
| `send(event)` | Send any event |

---

## RoutingState

Immutable state for navigation.

### Properties

| Property | Type | Description |
|----------|------|-------------|
| `isInitialized` | `bool` | Whether bloc is initialized |
| `stack` | `List<StackEntry>` | Navigation stack |
| `history` | `List<HistoryEntry>` | Navigation history |
| `pending` | `PendingNavigation?` | Current pending navigation |
| `error` | `RoutingError?` | Last navigation error |

### Getters

| Getter | Type | Description |
|--------|------|-------------|
| `current` | `StackEntry?` | Top of stack |
| `currentPath` | `String?` | Current route path |
| `currentParams` | `Map<String, String>` | Current route params |
| `stackDepth` | `int` | Number of routes in stack |
| `canPop` | `bool` | Whether pop is possible |
| `isNavigating` | `bool` | Whether guards are running |

---

## StackEntry

Represents a route in the navigation stack.

### Properties

| Property | Type | Description |
|----------|------|-------------|
| `route` | `RouteConfig` | Route configuration |
| `path` | `String` | Full path with params |
| `params` | `Map<String, String>` | Path parameters |
| `query` | `Map<String, String>` | Query parameters |
| `extra` | `Object?` | Extra data |
| `key` | `String` | Unique entry identifier |
| `pushedAt` | `DateTime` | When entry was pushed |

---

## HistoryEntry

Represents a navigation event in history.

### Properties

| Property | Type | Description |
|----------|------|-------------|
| `path` | `String` | Route path |
| `timestamp` | `DateTime` | When navigation occurred |
| `type` | `NavigationType` | Type of navigation |
| `timeOnRoute` | `Duration?` | Time spent on route (for pops) |

---

## NavigationType

Enum for navigation types.

| Value | Description |
|-------|-------------|
| `push` | New route pushed |
| `pop` | Route popped |
| `replace` | Route replaced |
| `reset` | Stack reset |

---

## Events

### InitializeRoutingEvent

Initialize the routing bloc with configuration.

```dart
InitializeRoutingEvent({
  required RoutingConfig config,
  String? initialPath,
})
```

### NavigateEvent

Navigate to a path.

```dart
NavigateEvent({
  required String path,
  Object? extra,
  bool replace = false,
  RouteTransition? transition,
})
```

### PopEvent

Pop the current route.

```dart
PopEvent({
  Object? result,
})
```

### PopUntilEvent

Pop routes until predicate matches.

```dart
PopUntilEvent({
  required bool Function(StackEntry entry) predicate,
})
```

### PopToRootEvent

Pop all routes except root.

```dart
PopToRootEvent()
```

### ResetStackEvent

Clear stack and navigate to path.

```dart
ResetStackEvent({
  required String path,
  Object? extra,
})
```

### RouteVisibleEvent

Emitted when a route becomes visible (internal).

```dart
RouteVisibleEvent({
  required String entryKey,
  required String path,
  required String title,
})
```

### RouteHiddenEvent

Emitted when a route becomes hidden (internal).

```dart
RouteHiddenEvent({
  required String entryKey,
  required String path,
  required Duration timeVisible,
})
```

---

## Configuration

### RoutingConfig

Root configuration for routing.

```dart
RoutingConfig({
  required List<RouteConfig> routes,
  List<RouteGuard> globalGuards = const [],
  RouteConfig? notFoundRoute,
  String initialPath = '/',
  int maxRedirects = 5,
})
```

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `routes` | `List<RouteConfig>` | required | Route definitions |
| `globalGuards` | `List<RouteGuard>` | `[]` | Guards for all routes |
| `notFoundRoute` | `RouteConfig?` | `null` | Fallback route |
| `initialPath` | `String` | `'/'` | Starting path |
| `maxRedirects` | `int` | `5` | Max redirect chain |

### RouteConfig

Individual route configuration.

```dart
RouteConfig({
  required String path,
  required Widget Function(RouteBuildContext ctx) builder,
  String? title,
  List<RouteGuard> guards = const [],
  List<RouteConfig> children = const [],
  RouteTransition? transition,
})
```

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `path` | `String` | required | Path pattern |
| `builder` | `Function` | required | Widget builder |
| `title` | `String?` | `null` | Route title |
| `guards` | `List<RouteGuard>` | `[]` | Route guards |
| `children` | `List<RouteConfig>` | `[]` | Nested routes |
| `transition` | `RouteTransition?` | `null` | Default transition |

---

## RouteBuildContext

Context passed to route builders.

### Properties

| Property | Type | Description |
|----------|------|-------------|
| `params` | `Map<String, String>` | Path parameters |
| `query` | `Map<String, String>` | Query parameters |
| `extra` | `Object?` | Extra data |
| `entry` | `StackEntry` | Stack entry |

### Methods

| Method | Returns | Description |
|--------|---------|-------------|
| `extraAs<T>()` | `T?` | Typed extra access |

---

## Route Guards

### RouteGuard

Abstract base class for guards.

```dart
abstract class RouteGuard {
  String get name;
  int get priority => 0;
  Future<GuardResult> check(RouteContext context);
}
```

### RouteContext

Context passed to guards.

| Property | Type | Description |
|----------|------|-------------|
| `targetPath` | `String` | Target path |
| `params` | `Map<String, String>` | Path parameters |
| `query` | `Map<String, String>` | Query parameters |
| `currentState` | `RoutingState` | Current state |
| `targetRoute` | `RouteConfig` | Target route |

### GuardResult

Sealed class for guard results.

```dart
// Allow navigation
const GuardResult.allow()

// Redirect to another path
GuardResult.redirect(String path, {String? returnTo})

// Block navigation
GuardResult.block(String reason)
```

---

## Errors

### RoutingError

Sealed base class for routing errors.

| Error | Description |
|-------|-------------|
| `RouteNotFoundError` | No route matches path |
| `GuardBlockedError` | Guard blocked navigation |
| `GuardExceptionError` | Guard threw exception |
| `RedirectLoopError` | Redirect chain exceeded max |
| `InvalidPathError` | Invalid path format |
| `CannotPopError` | Cannot pop at root |

---

## Navigator 2.0 Integration

### JuiceRouterDelegate

Router delegate for MaterialApp.router.

```dart
JuiceRouterDelegate({
  required RoutingBloc routingBloc,
})
```

### JuiceRouteInformationParser

Route information parser.

```dart
const JuiceRouteInformationParser()
```

---

## RouteTransition

Enum for route transitions.

| Value | Description |
|-------|-------------|
| `platform` | Platform default |
| `none` | No animation |
| `fade` | Fade in/out |
| `slideRight` | Slide from right |
| `slideBottom` | Slide from bottom |
| `scale` | Scale from center |

---

## Rebuild Groups

| Group | Updates When |
|-------|--------------|
| `routing.stack` | Stack changes |
| `routing.current` | Current route changes |
| `routing.pending` | Navigation in progress |
| `routing.history` | History entry added |
| `routing.error` | Error occurred |
