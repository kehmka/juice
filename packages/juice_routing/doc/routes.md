---
layout: default
title: Route Configuration
nav_order: 3
---

# Route Configuration

This guide covers how to define routes, use parameters, create nested routes, and configure transitions.

## Basic Route Definition

Routes are defined using `RouteConfig`:

```dart
RouteConfig(
  path: '/profile',
  title: 'Profile',
  builder: (ctx) => const ProfileScreen(),
)
```

## Path Parameters

Use `:paramName` to define dynamic segments:

```dart
RouteConfig(
  path: '/users/:userId',
  builder: (ctx) => UserScreen(userId: ctx.params['userId']!),
)

RouteConfig(
  path: '/posts/:postId/comments/:commentId',
  builder: (ctx) => CommentScreen(
    postId: ctx.params['postId']!,
    commentId: ctx.params['commentId']!,
  ),
)
```

Access parameters in your builder via `ctx.params`.

## Query Parameters

Query parameters are automatically parsed:

```dart
// Navigation: routingBloc.navigate('/search?q=flutter&sort=recent')

RouteConfig(
  path: '/search',
  builder: (ctx) => SearchScreen(
    query: ctx.query['q'] ?? '',
    sort: ctx.query['sort'] ?? 'relevance',
  ),
)
```

Access query parameters via `ctx.query`.

## Wildcard Routes

Use `*` to match any remaining path:

```dart
RouteConfig(
  path: '/files/*',
  builder: (ctx) => FileViewer(
    filePath: ctx.params['*']!,  // 'a/b/c' for '/files/a/b/c'
  ),
)
```

## Nested Routes

Define child routes for hierarchical navigation:

```dart
RouteConfig(
  path: '/settings',
  builder: (ctx) => const SettingsScreen(),
  children: [
    RouteConfig(
      path: 'account',  // Matches '/settings/account'
      builder: (ctx) => const AccountSettingsScreen(),
    ),
    RouteConfig(
      path: 'privacy',  // Matches '/settings/privacy'
      builder: (ctx) => const PrivacySettingsScreen(),
    ),
    RouteConfig(
      path: 'notifications',  // Matches '/settings/notifications'
      builder: (ctx) => const NotificationSettingsScreen(),
    ),
  ],
)
```

Child paths are relative to the parent.

## Extra Data

Pass non-URL data with navigation:

```dart
// Navigate with extra data
routingBloc.navigate(
  '/checkout',
  extra: CartData(items: cartItems, total: 99.99),
);

// Access in builder
RouteConfig(
  path: '/checkout',
  builder: (ctx) {
    final cart = ctx.extraAs<CartData>();
    return CheckoutScreen(cart: cart);
  },
)
```

Note: Extra data is not preserved through redirects.

## Route Transitions

Configure transitions per-route or per-navigation:

### Per-Route Default

```dart
RouteConfig(
  path: '/modal',
  builder: (ctx) => const ModalScreen(),
  transition: RouteTransition.slideBottom,
)
```

### Per-Navigation Override

```dart
routingBloc.navigate(
  '/profile/123',
  transition: RouteTransition.fade,
);
```

### Available Transitions

| Transition | Description |
|------------|-------------|
| `RouteTransition.platform` | Platform default (Cupertino/Material) |
| `RouteTransition.none` | No animation |
| `RouteTransition.fade` | Fade in/out |
| `RouteTransition.slideRight` | Slide from right |
| `RouteTransition.slideBottom` | Slide from bottom |
| `RouteTransition.scale` | Scale from center |

## Not Found Route

Define a fallback for unmatched paths:

```dart
final appRoutes = RoutingConfig(
  routes: [...],
  notFoundRoute: RouteConfig(
    path: '/404',
    title: 'Not Found',
    builder: (ctx) => NotFoundScreen(
      requestedPath: ctx.entry.path,
    ),
  ),
);
```

## Global Guards

Apply guards to all routes:

```dart
final appRoutes = RoutingConfig(
  routes: [...],
  globalGuards: [
    LoggingGuard(),      // Runs first (priority 1)
    MaintenanceGuard(),  // Runs second (priority 10)
  ],
);
```

See [Route Guards](guards.html) for more details.

## Configuration Options

### RoutingConfig

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `routes` | `List<RouteConfig>` | required | Route definitions |
| `globalGuards` | `List<RouteGuard>` | `[]` | Guards for all routes |
| `notFoundRoute` | `RouteConfig?` | `null` | Fallback for unmatched paths |
| `initialPath` | `String` | `'/'` | Starting path |
| `maxRedirects` | `int` | `5` | Max redirect chain length |

### RouteConfig

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `path` | `String` | required | Path pattern |
| `builder` | `Widget Function(RouteBuildContext)` | required | Widget builder |
| `title` | `String?` | `null` | Route title |
| `guards` | `List<RouteGuard>` | `[]` | Route-specific guards |
| `children` | `List<RouteConfig>` | `[]` | Nested routes |
| `transition` | `RouteTransition?` | `null` | Default transition |

## RouteBuildContext

The context passed to route builders:

```dart
class RouteBuildContext {
  /// Path parameters (e.g., :userId → '123')
  final Map<String, String> params;

  /// Query parameters (e.g., ?tab=posts)
  final Map<String, String> query;

  /// Non-URL state from NavigateEvent.extra
  final Object? extra;

  /// The stack entry for this route
  final StackEntry entry;

  /// Typed extra with null safety
  T? extraAs<T>();
}
```

## Path Resolution Order

When matching paths, the resolver checks:

1. Exact matches first
2. Parameterized routes (`:param`)
3. Wildcard routes (`*`)
4. Child routes (recursively)
5. Not found route (if configured)

More specific patterns take precedence over wildcards.
