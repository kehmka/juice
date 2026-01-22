import 'package:flutter/widgets.dart';

import 'route_path.dart';

/// Route information parser for Navigator 2.0.
///
/// Converts between system route information (from browser URL bar, deep links)
/// and [RoutePath] objects used by the router.
class JuiceRouteInformationParser extends RouteInformationParser<RoutePath> {
  const JuiceRouteInformationParser();

  @override
  Future<RoutePath> parseRouteInformation(
      RouteInformation routeInformation) async {
    final uri = routeInformation.uri;
    return RoutePath(
      path: uri.path.isEmpty ? '/' : uri.path,
      queryParameters: uri.queryParameters,
    );
  }

  @override
  RouteInformation? restoreRouteInformation(RoutePath configuration) {
    return RouteInformation(uri: Uri.parse(configuration.toUri()));
  }
}
