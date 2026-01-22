import 'package:juice/juice.dart';

import '../routing_bloc.dart';
import '../routing_events.dart';

/// Use case for handling route visibility events.
///
/// These events are sent by the navigator observer for time-on-route tracking.
/// Currently just logs the events; future implementation may track visibility duration.
class RouteVisibleUseCase
    extends BlocUseCase<RoutingBloc, RouteVisibleEvent> {
  @override
  Future<void> execute(RouteVisibleEvent event) async {
    log('Route became visible: ${event.routeKey}');
    // Future: Could track visibility start time
  }
}

/// Use case for handling route hidden events.
///
/// These events are sent by the navigator observer for time-on-route tracking.
class RouteHiddenUseCase extends BlocUseCase<RoutingBloc, RouteHiddenEvent> {
  @override
  Future<void> execute(RouteHiddenEvent event) async {
    log('Route became hidden: ${event.routeKey}');
    // Future: Could calculate and record visibility duration
  }
}
