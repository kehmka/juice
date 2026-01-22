import 'package:flutter/widgets.dart';

import '../routing_bloc.dart';
import '../routing_events.dart';

/// Navigator observer that tracks route visibility for time-on-route metrics.
///
/// Sends [RouteVisibleEvent] and [RouteHiddenEvent] to the [RoutingBloc]
/// when routes become visible or hidden.
class JuiceNavigatorObserver extends NavigatorObserver {
  final RoutingBloc routingBloc;

  JuiceNavigatorObserver({required this.routingBloc});

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _notifyVisible(route);
    if (previousRoute != null) {
      _notifyHidden(previousRoute);
    }
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _notifyHidden(route);
    if (previousRoute != null) {
      _notifyVisible(previousRoute);
    }
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _notifyHidden(route);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (oldRoute != null) {
      _notifyHidden(oldRoute);
    }
    if (newRoute != null) {
      _notifyVisible(newRoute);
    }
  }

  void _notifyVisible(Route<dynamic> route) {
    final key = _extractKey(route);
    if (key != null) {
      routingBloc.send(RouteVisibleEvent(routeKey: key));
    }
  }

  void _notifyHidden(Route<dynamic> route) {
    final key = _extractKey(route);
    if (key != null) {
      routingBloc.send(RouteHiddenEvent(routeKey: key));
    }
  }

  String? _extractKey(Route<dynamic> route) {
    final settings = route.settings;
    if (settings.name != null) {
      return settings.name;
    }
    // Try to extract from ValueKey
    if (settings is Page && settings.key is ValueKey) {
      final valueKey = settings.key as ValueKey;
      return valueKey.value?.toString();
    }
    return null;
  }
}
