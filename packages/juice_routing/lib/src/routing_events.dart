import 'package:juice/juice.dart';

import 'routing_config.dart';
import 'routing_state.dart';
import 'routing_types.dart';

/// Base class for all routing events.
///
/// Events are sent to [RoutingBloc] to trigger navigation actions.
abstract class RoutingEvent extends EventBase {
  RoutingEvent({super.groupsToRebuild});
}

/// Initialize the routing system with configuration.
///
/// Must be sent before any navigation events.
/// Resolves the initial path and creates the initial stack.
///
/// Example:
/// ```dart
/// routingBloc.send(InitializeRoutingEvent(config: routingConfig));
/// ```
class InitializeRoutingEvent extends RoutingEvent {
  /// The routing configuration
  final RoutingConfig config;

  /// Optional override for initial path (defaults to config.initialPath)
  final String? initialPath;

  InitializeRoutingEvent({
    required this.config,
    this.initialPath,
  });

  @override
  String toString() => 'InitializeRoutingEvent(initialPath: ${initialPath ?? config.initialPath})';
}

/// Navigate to a new path.
///
/// Guards will be checked before navigation commits.
/// If [replace] is true, replaces the current stack entry instead of pushing.
///
/// Example:
/// ```dart
/// routingBloc.send(NavigateEvent(path: '/profile/123'));
///
/// // With extra data
/// routingBloc.send(NavigateEvent(
///   path: '/product',
///   extra: productData,
/// ));
///
/// // Replace current route
/// routingBloc.send(NavigateEvent(
///   path: '/home',
///   replace: true,
/// ));
/// ```
class NavigateEvent extends RoutingEvent {
  /// The path to navigate to
  final String path;

  /// Extra data to pass to the route builder
  final Object? extra;

  /// If true, replace current entry instead of pushing
  final bool replace;

  /// Override transition animation for this navigation
  final RouteTransition? transition;

  NavigateEvent({
    required this.path,
    this.extra,
    this.replace = false,
    this.transition,
  });

  @override
  String toString() => 'NavigateEvent($path${replace ? ', replace' : ''})';
}

/// Pop the current route from the stack.
///
/// This event bypasses guards and executes immediately.
/// Fails with [CannotPopError] if at root (single entry on stack).
///
/// Example:
/// ```dart
/// routingBloc.send(PopEvent());
///
/// // With result data
/// routingBloc.send(PopEvent(result: selectedItem));
/// ```
class PopEvent extends RoutingEvent {
  /// Optional result to pass back to the previous route
  final Object? result;

  PopEvent({this.result});

  @override
  String toString() => 'PopEvent(${result != null ? 'with result' : ''})';
}

/// Pop routes until a condition is met.
///
/// Bypasses guards. Pops entries from the stack until [predicate] returns true.
/// The entry where predicate returns true remains on the stack.
///
/// Example:
/// ```dart
/// // Pop until we find '/dashboard'
/// routingBloc.send(PopUntilEvent(
///   predicate: (entry) => entry.path == '/dashboard',
/// ));
/// ```
class PopUntilEvent extends RoutingEvent {
  /// Predicate to test each stack entry.
  /// Popping stops when this returns true (that entry stays).
  final bool Function(StackEntry entry) predicate;

  PopUntilEvent({required this.predicate});

  @override
  String toString() => 'PopUntilEvent()';
}

/// Pop all routes except the root.
///
/// Bypasses guards. Clears the stack down to the first entry.
///
/// Example:
/// ```dart
/// routingBloc.send(PopToRootEvent());
/// ```
class PopToRootEvent extends RoutingEvent {
  PopToRootEvent();

  @override
  String toString() => 'PopToRootEvent()';
}

/// Reset the entire stack to a single new route.
///
/// Guards are run on the new path. If guards pass, the entire
/// stack is replaced with a single entry for the new path.
///
/// Example:
/// ```dart
/// // After logout, reset to login screen
/// routingBloc.send(ResetStackEvent(path: '/login'));
/// ```
class ResetStackEvent extends RoutingEvent {
  /// The path to reset the stack to
  final String path;

  /// Extra data for the new route
  final Object? extra;

  ResetStackEvent({
    required this.path,
    this.extra,
  });

  @override
  String toString() => 'ResetStackEvent($path)';
}

/// Notify that a route became visible.
///
/// Used internally by [JuiceNavigatorObserver] for time-on-route tracking.
/// You typically don't need to send this event manually.
class RouteVisibleEvent extends RoutingEvent {
  /// The key of the route that became visible
  final String routeKey;

  RouteVisibleEvent({required this.routeKey});

  @override
  String toString() => 'RouteVisibleEvent($routeKey)';
}

/// Notify that a route became hidden.
///
/// Used internally by [JuiceNavigatorObserver] for time-on-route tracking.
/// You typically don't need to send this event manually.
class RouteHiddenEvent extends RoutingEvent {
  /// The key of the route that became hidden
  final String routeKey;

  RouteHiddenEvent({required this.routeKey});

  @override
  String toString() => 'RouteHiddenEvent($routeKey)';
}
