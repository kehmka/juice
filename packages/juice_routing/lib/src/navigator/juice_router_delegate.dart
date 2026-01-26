import 'package:juice/juice.dart';

import '../route_context.dart';
import '../routing_bloc.dart';
import '../routing_events.dart';
import '../routing_state.dart';
import '../routing_types.dart';
import 'route_path.dart';
import 'visibility_observer.dart';

/// Router delegate for Navigator 2.0 integration.
///
/// Builds the Navigator widget tree from [RoutingBloc] state and
/// handles back button / system pop requests.
///
/// ## Usage
///
/// ```dart
/// MaterialApp.router(
///   routerDelegate: JuiceRouterDelegate(routingBloc: routingBloc),
///   routeInformationParser: const JuiceRouteInformationParser(),
/// )
/// ```
class JuiceRouterDelegate extends RouterDelegate<RoutePath>
    with ChangeNotifier, PopNavigatorRouterDelegateMixin<RoutePath> {
  final RoutingBloc routingBloc;
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  late final StreamSubscription<StreamStatus<RoutingState>> _subscription;
  late final JuiceNavigatorObserver _observer;

  JuiceRouterDelegate({required this.routingBloc}) {
    _observer = JuiceNavigatorObserver(routingBloc: routingBloc);
    // Subscribe to bloc state changes
    _subscription = routingBloc.stream.listen((_) {
      notifyListeners();
    });
  }

  @override
  GlobalKey<NavigatorState> get navigatorKey => _navigatorKey;

  @override
  RoutePath? get currentConfiguration {
    final current = routingBloc.state.current;
    if (current == null) return null;

    return RoutePath(
      path: current.path,
      queryParameters: current.query,
    );
  }

  @override
  Future<void> setNewRoutePath(RoutePath configuration) async {
    // Handle incoming deep links / URL changes
    final fullPath = configuration.toUri();
    routingBloc.navigate(fullPath);
  }

  @override
  Widget build(BuildContext context) {
    final state = routingBloc.state;

    if (!state.isInitialized || state.stack.isEmpty) {
      // Show loading or empty state while initializing
      return Navigator(
        pages: const [
          MaterialPage(
            key: ValueKey('loading'),
            child: Scaffold(
              body: Center(child: CircularProgressIndicator()),
            ),
          ),
        ],
        onDidRemovePage: (_) {},  // No-op while loading
      );
    }

    // Build pages from stack
    final pages = state.stack.map((entry) => _buildPage(entry)).toList();

    return Navigator(
      key: navigatorKey,
      pages: pages,
      onDidRemovePage: _onDidRemovePage,
      observers: [_observer],
    );
  }

  Page<dynamic> _buildPage(StackEntry entry) {
    final route = entry.route;
    final buildContext = RouteBuildContext(
      params: entry.params,
      query: entry.query,
      extra: entry.extra,
      entry: entry,
    );

    final child = route.builder(buildContext);

    // Handle custom transitions
    if (route.transition == RouteTransition.custom && route.pageBuilder != null) {
      return route.pageBuilder!(buildContext, child);
    }

    // Default to MaterialPage with appropriate transition
    return _buildMaterialPage(
      key: ValueKey(entry.key),
      child: child,
      name: route.title ?? entry.path,
      transition: route.transition,
    );
  }

  Page<dynamic> _buildMaterialPage({
    required LocalKey key,
    required Widget child,
    required String name,
    required RouteTransition transition,
  }) {
    switch (transition) {
      case RouteTransition.none:
        return _NoAnimationPage(key: key, child: child, name: name);
      case RouteTransition.fade:
        return _FadeAnimationPage(key: key, child: child, name: name);
      case RouteTransition.slideRight:
        return _SlideRightAnimationPage(key: key, child: child, name: name);
      case RouteTransition.slideBottom:
        return _SlideBottomAnimationPage(key: key, child: child, name: name);
      case RouteTransition.scale:
        return _ScaleAnimationPage(key: key, child: child, name: name);
      case RouteTransition.platform:
      case RouteTransition.custom:
        return MaterialPage(key: key, child: child, name: name);
    }
  }

  void _onDidRemovePage(Page<Object?> page) {
    // Send pop event to bloc when a page is removed
    routingBloc.send(PopEvent());
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}

// Custom page classes for different transitions

class _NoAnimationPage extends Page<void> {
  final Widget child;

  const _NoAnimationPage({
    required super.key,
    required this.child,
    super.name,
  });

  @override
  Route<void> createRoute(BuildContext context) {
    return PageRouteBuilder(
      settings: this,
      pageBuilder: (context, animation, secondaryAnimation) => child,
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
    );
  }
}

class _FadeAnimationPage extends Page<void> {
  final Widget child;

  const _FadeAnimationPage({
    required super.key,
    required this.child,
    super.name,
  });

  @override
  Route<void> createRoute(BuildContext context) {
    return PageRouteBuilder(
      settings: this,
      pageBuilder: (context, animation, secondaryAnimation) => child,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(opacity: animation, child: child);
      },
    );
  }
}

class _SlideRightAnimationPage extends Page<void> {
  final Widget child;

  const _SlideRightAnimationPage({
    required super.key,
    required this.child,
    super.name,
  });

  @override
  Route<void> createRoute(BuildContext context) {
    return PageRouteBuilder(
      settings: this,
      pageBuilder: (context, animation, secondaryAnimation) => child,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        const begin = Offset(1.0, 0.0);
        const end = Offset.zero;
        const curve = Curves.easeInOut;
        final tween = Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
        return SlideTransition(position: animation.drive(tween), child: child);
      },
    );
  }
}

class _SlideBottomAnimationPage extends Page<void> {
  final Widget child;

  const _SlideBottomAnimationPage({
    required super.key,
    required this.child,
    super.name,
  });

  @override
  Route<void> createRoute(BuildContext context) {
    return PageRouteBuilder(
      settings: this,
      pageBuilder: (context, animation, secondaryAnimation) => child,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        const begin = Offset(0.0, 1.0);
        const end = Offset.zero;
        const curve = Curves.easeInOut;
        final tween = Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
        return SlideTransition(position: animation.drive(tween), child: child);
      },
    );
  }
}

class _ScaleAnimationPage extends Page<void> {
  final Widget child;

  const _ScaleAnimationPage({
    required super.key,
    required this.child,
    super.name,
  });

  @override
  Route<void> createRoute(BuildContext context) {
    return PageRouteBuilder(
      settings: this,
      pageBuilder: (context, animation, secondaryAnimation) => child,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        const curve = Curves.easeInOut;
        final tween = Tween(begin: 0.0, end: 1.0).chain(CurveTween(curve: curve));
        return ScaleTransition(scale: animation.drive(tween), child: child);
      },
    );
  }
}
