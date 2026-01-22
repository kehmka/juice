import 'routing_config.dart';

/// Result of resolving a path to a route.
class ResolvedRoute {
  /// The matched route configuration
  final RouteConfig route;

  /// Path parameters extracted from the URL
  final Map<String, String> params;

  /// Query parameters from the URL
  final Map<String, String> query;

  /// The full matched path (without query string)
  final String matchedPath;

  const ResolvedRoute({
    required this.route,
    required this.params,
    required this.query,
    required this.matchedPath,
  });

  @override
  String toString() => 'ResolvedRoute($matchedPath, params: $params)';
}

/// Resolves URL paths to route configurations.
///
/// Supports:
/// - Literal segments: `/home`, `/users`
/// - Parameters: `:param` captures a segment as a named parameter
/// - Wildcards: `*` captures remaining path (must be last segment)
/// - Nested routes: Children inherit parent path
///
/// Example:
/// ```dart
/// final resolver = PathResolver(config);
/// final resolved = resolver.resolve('/profile/123/settings?tab=privacy');
/// // resolved.route -> ProfileSettingsRoute
/// // resolved.params -> {'userId': '123'}
/// // resolved.query -> {'tab': 'privacy'}
/// ```
class PathResolver {
  final RoutingConfig _config;
  final List<_FlattenedRoute> _flatRoutes = [];

  PathResolver(this._config) {
    _flattenRoutes(_config.routes, '');
  }

  /// Flatten the route tree into a list for matching.
  void _flattenRoutes(List<RouteConfig> routes, String parentPath) {
    for (final route in routes) {
      final fullPath = _joinPaths(parentPath, route.path);
      _flatRoutes.add(_FlattenedRoute(route: route, fullPath: fullPath));

      if (route.children.isNotEmpty) {
        _flattenRoutes(route.children, fullPath);
      }
    }
  }

  /// Join parent and child paths, handling leading/trailing slashes.
  String _joinPaths(String parent, String child) {
    if (parent.isEmpty) return child;
    if (child.isEmpty) return parent;

    final parentNormalized =
        parent.endsWith('/') ? parent.substring(0, parent.length - 1) : parent;
    final childNormalized = child.startsWith('/') ? child.substring(1) : child;

    if (childNormalized.isEmpty) return parentNormalized;
    return '$parentNormalized/$childNormalized';
  }

  /// Resolve a path to a route.
  ///
  /// Returns null if no route matches.
  ResolvedRoute? resolve(String path) {
    // Parse query string
    final uri = Uri.parse(path);
    final pathOnly = uri.path;
    final query = uri.queryParameters;

    // Normalize path
    final normalizedPath = _normalizePath(pathOnly);

    // Try to match each route
    for (final flatRoute in _flatRoutes) {
      final params = _matchPath(flatRoute.fullPath, normalizedPath);
      if (params != null) {
        return ResolvedRoute(
          route: flatRoute.route,
          params: params,
          query: Map.unmodifiable(query),
          matchedPath: normalizedPath,
        );
      }
    }

    // Check for notFoundRoute
    if (_config.notFoundRoute != null) {
      return ResolvedRoute(
        route: _config.notFoundRoute!,
        params: const {},
        query: Map.unmodifiable(query),
        matchedPath: normalizedPath,
      );
    }

    return null;
  }

  /// Normalize a path by ensuring it starts with / and removing trailing /.
  String _normalizePath(String path) {
    var normalized = path;

    // Ensure leading slash
    if (!normalized.startsWith('/')) {
      normalized = '/$normalized';
    }

    // Remove trailing slash (except for root)
    if (normalized.length > 1 && normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }

    return normalized;
  }

  /// Match a pattern against a path.
  ///
  /// Returns extracted parameters if match succeeds, null otherwise.
  Map<String, String>? _matchPath(String pattern, String path) {
    final patternSegments = _splitPath(pattern);
    final pathSegments = _splitPath(path);

    final params = <String, String>{};

    var patternIndex = 0;
    var pathIndex = 0;

    while (patternIndex < patternSegments.length) {
      final patternSegment = patternSegments[patternIndex];

      // Wildcard: capture rest of path
      if (patternSegment == '*') {
        if (patternIndex != patternSegments.length - 1) {
          // Wildcard must be last segment (invalid pattern)
          return null;
        }
        // Capture remaining segments
        final remaining = pathSegments.sublist(pathIndex).join('/');
        params['*'] = remaining;
        return Map.unmodifiable(params);
      }

      // Check if we have a path segment to match
      if (pathIndex >= pathSegments.length) {
        return null; // Pattern has more segments than path
      }

      final pathSegment = pathSegments[pathIndex];

      // Parameter: capture segment value
      if (patternSegment.startsWith(':')) {
        final paramName = patternSegment.substring(1);
        params[paramName] = Uri.decodeComponent(pathSegment);
      }
      // Literal: must match exactly
      else if (patternSegment != pathSegment) {
        return null;
      }

      patternIndex++;
      pathIndex++;
    }

    // Pattern matched, but path has extra segments
    if (pathIndex < pathSegments.length) {
      return null;
    }

    return Map.unmodifiable(params);
  }

  /// Split a path into segments, filtering empty segments.
  List<String> _splitPath(String path) {
    return path.split('/').where((s) => s.isNotEmpty).toList();
  }
}

/// Internal class to hold a flattened route with its full path.
class _FlattenedRoute {
  final RouteConfig route;
  final String fullPath;

  const _FlattenedRoute({
    required this.route,
    required this.fullPath,
  });
}
