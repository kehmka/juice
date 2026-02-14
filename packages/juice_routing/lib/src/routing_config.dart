import 'package:flutter/widgets.dart';

import 'route_context.dart';
import 'route_guard.dart';
import 'routing_types.dart';

/// Builder function for creating route widgets.
typedef RouteWidgetBuilder = Widget Function(RouteBuildContext context);

/// Builder function for custom page transitions.
typedef PageBuilder = Page<dynamic> Function(
  RouteBuildContext context,
  Widget child,
);

/// Configuration for a single route.
///
/// Routes can have parameters (`:param`), wildcards (`*`), and nested children.
///
/// Example:
/// ```dart
/// RouteConfig(
///   path: '/profile/:userId',
///   builder: (ctx) => ProfileScreen(userId: ctx.params['userId']!),
///   guards: [AuthGuard()],
///   children: [
///     RouteConfig(
///       path: 'settings',  // Matches /profile/:userId/settings
///       builder: (ctx) => ProfileSettingsScreen(),
///     ),
///   ],
/// )
/// ```
class RouteConfig {
  /// The path pattern for this route.
  ///
  /// Supports:
  /// - Literal segments: `/home`, `/users`
  /// - Parameters: `:param` captures a segment as named parameter
  /// - Wildcards: `*` captures remaining path (must be last segment)
  final String path;

  /// Builder function to create the widget for this route.
  final RouteWidgetBuilder builder;

  /// Optional title for this route (for browser tab, accessibility).
  final String? title;

  /// Guards to run before allowing navigation to this route.
  /// Combined with global guards; route guards run after global guards.
  final List<RouteGuard> guards;

  /// Child routes nested under this route.
  final List<RouteConfig> children;

  /// Scope name for ScopeLifecycleBloc integration.
  /// When set, entering this route activates the named scope.
  final String? scopeName;

  /// Transition animation for this route.
  final RouteTransition transition;

  /// Custom page builder for [RouteTransition.custom].
  final PageBuilder? pageBuilder;

  const RouteConfig({
    required this.path,
    required this.builder,
    this.title,
    this.guards = const [],
    this.children = const [],
    this.scopeName,
    this.transition = RouteTransition.platform,
    this.pageBuilder,
  });

  @override
  String toString() => 'RouteConfig($path)';
}

/// Top-level routing configuration.
///
/// Defines all routes, global guards, and navigation behavior.
///
/// Example:
/// ```dart
/// final config = RoutingConfig(
///   routes: [
///     RouteConfig(path: '/', builder: (ctx) => HomeScreen()),
///     RouteConfig(path: '/login', builder: (ctx) => LoginScreen()),
///     RouteConfig(
///       path: '/dashboard',
///       builder: (ctx) => DashboardScreen(),
///       guards: [AuthGuard()],
///     ),
///   ],
///   globalGuards: [LoggingGuard()],
///   notFoundRoute: RouteConfig(
///     path: '/404',
///     builder: (ctx) => NotFoundScreen(),
///   ),
///   initialPath: '/',
///   maxRedirects: 5,
/// );
/// ```
class RoutingConfig {
  /// All route configurations.
  final List<RouteConfig> routes;

  /// Guards that run for every navigation.
  /// Global guards run before route-specific guards.
  final List<RouteGuard> globalGuards;

  /// Fallback route when path doesn't match any route.
  /// If null, [RouteNotFoundError] is emitted instead.
  final RouteConfig? notFoundRoute;

  /// Initial path to navigate to on app start.
  final String initialPath;

  /// Maximum number of redirects before [RedirectLoopError].
  /// Defaults to 5.
  final int maxRedirects;

  /// Maximum number of history entries to retain.
  /// Oldest entries are trimmed when this limit is exceeded.
  /// Defaults to 100.
  final int maxHistorySize;

  const RoutingConfig({
    required this.routes,
    this.globalGuards = const [],
    this.notFoundRoute,
    this.initialPath = '/',
    this.maxRedirects = 5,
    this.maxHistorySize = 100,
  });

  @override
  String toString() => 'RoutingConfig(${routes.length} routes)';
}
