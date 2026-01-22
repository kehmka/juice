import 'package:flutter/foundation.dart';

/// Value object representing a route path for Navigator 2.0.
///
/// Used by [JuiceRouteInformationParser] to communicate route
/// information between the system and the router.
@immutable
class RoutePath {
  /// The path portion of the URL
  final String path;

  /// Query parameters from the URL
  final Map<String, String> queryParameters;

  const RoutePath({
    required this.path,
    this.queryParameters = const {},
  });

  /// Parse a URI string into a RoutePath.
  factory RoutePath.fromUri(String uri) {
    final parsed = Uri.parse(uri);
    return RoutePath(
      path: parsed.path.isEmpty ? '/' : parsed.path,
      queryParameters: parsed.queryParameters,
    );
  }

  /// Convert to a URI string.
  String toUri() {
    if (queryParameters.isEmpty) {
      return path;
    }
    final uri = Uri(path: path, queryParameters: queryParameters);
    return uri.toString();
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RoutePath &&
          runtimeType == other.runtimeType &&
          path == other.path &&
          _mapEquals(queryParameters, other.queryParameters);

  @override
  int get hashCode => Object.hash(path, Object.hashAll(queryParameters.entries));

  bool _mapEquals(Map<String, String> a, Map<String, String> b) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (a[key] != b[key]) return false;
    }
    return true;
  }

  @override
  String toString() => 'RoutePath($path${queryParameters.isNotEmpty ? '?${queryParameters.entries.map((e) => '${e.key}=${e.value}').join('&')}' : ''})';
}
