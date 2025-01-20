import '../aviator.dart';

/// Represents a deep link route with prerequisites
class DeepLinkRoute {
  final List<String> path;
  final Map<String, dynamic> args;
  final List<String> requiredData;

  const DeepLinkRoute({
    required this.path,
    this.args = const {},
    this.requiredData = const [],
  });
}

/// Configuration for deep link handling
class DeepLinkConfig {
  final String authRoute;
  final Map<String, DeepLinkRoute> routes;
  final Future<bool> Function()? checkAuth;
  final Future<void> Function(String)? loadData;

  const DeepLinkConfig({
    required this.authRoute,
    required this.routes,
    this.checkAuth,
    this.loadData,
  });
}

/// Specialized aviator for handling deep links
class DeepLinkAviator extends AviatorBase {
  @override
  final String name;
  final NavigateWhere _navigate;
  final DeepLinkConfig _config;

  DeepLinkAviator({
    required this.name,
    required NavigateWhere navigate,
    required DeepLinkConfig config,
  })  : _navigate = navigate,
        _config = config;

  @override
  NavigateWhere get navigateWhere => (args) async {
        final String deepLink = args['deepLink'];

        // Find matching route
        final route = _config.routes[deepLink];
        if (route == null) {
          throw ArgumentError('No route found for deep link: $deepLink');
        }

        // Check authentication if needed
        if (_config.checkAuth != null) {
          final isAuthenticated = await _config.checkAuth!();
          if (!isAuthenticated) {
            _navigate({
              ...args,
              'route': _config.authRoute,
              'isAuthRedirect': true,
            });
            return;
          }
        }

        // Load any required data
        if (_config.loadData != null) {
          for (final dataKey in route.requiredData) {
            await _config.loadData!(dataKey);
          }
        }

        // Execute navigation steps
        for (int i = 0; i < route.path.length; i++) {
          final isLast = i == route.path.length - 1;
          final screen = route.path[i];

          _navigate({
            ...args,
            'route': screen,
            'isLastStep': isLast,
            'routeArgs': isLast ? route.args : null,
          });
        }
      };

  @override
  Future<void> close() async {}
}
