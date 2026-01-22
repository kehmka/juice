import 'package:flutter/foundation.dart';

import 'routing_config.dart';
import 'routing_state.dart';

/// Context passed to route guards during navigation checks.
///
/// Provides guards with information about the navigation attempt
/// so they can make informed allow/redirect/block decisions.
@immutable
class RouteContext {
  /// The path being navigated to
  final String targetPath;

  /// Path parameters extracted from the URL (e.g., :userId -> '123')
  final Map<String, String> params;

  /// Query parameters from the URL
  final Map<String, String> query;

  /// The current routing state before this navigation
  final RoutingState currentState;

  /// The route configuration being navigated to
  final RouteConfig targetRoute;

  const RouteContext({
    required this.targetPath,
    required this.params,
    required this.query,
    required this.currentState,
    required this.targetRoute,
  });

  @override
  String toString() => 'RouteContext($targetPath)';
}

/// Context passed to route builders when constructing widgets.
///
/// Provides builders with access to route parameters, query strings,
/// and extra data passed during navigation.
@immutable
class RouteBuildContext {
  /// Path parameters extracted from the URL
  final Map<String, String> params;

  /// Query parameters from the URL
  final Map<String, String> query;

  /// Extra data passed via NavigateEvent
  final Object? extra;

  /// The stack entry this build context is for
  final StackEntry entry;

  const RouteBuildContext({
    required this.params,
    required this.query,
    required this.extra,
    required this.entry,
  });

  /// Typed access to extra data.
  ///
  /// Throws [TypeError] if extra is not of type T.
  /// Returns null if extra is null.
  ///
  /// Example:
  /// ```dart
  /// final product = context.extraAs<Product>();
  /// ```
  T? extraAs<T>() {
    if (extra == null) return null;
    return extra as T;
  }

  @override
  String toString() => 'RouteBuildContext(${entry.path})';
}
