import 'package:juice/juice.dart';

import '../routing_bloc.dart';
import '../routing_events.dart';

/// Use case for handling route visibility events.
///
/// Sent by the navigator observer when a route becomes visible.
/// This is an extension point — subclass and override [execute] to add
/// custom visibility tracking (e.g., analytics, time-on-route measurement).
class RouteVisibleUseCase
    extends BlocUseCase<RoutingBloc, RouteVisibleEvent> {
  @override
  Future<void> execute(RouteVisibleEvent event) async {
    // Extension point: override to track route visibility.
  }
}

/// Use case for handling route hidden events.
///
/// Sent by the navigator observer when a route is no longer visible.
/// This is an extension point — subclass and override [execute] to add
/// custom visibility tracking (e.g., analytics, time-on-route measurement).
class RouteHiddenUseCase extends BlocUseCase<RoutingBloc, RouteHiddenEvent> {
  @override
  Future<void> execute(RouteHiddenEvent event) async {
    // Extension point: override to track route visibility.
  }
}
