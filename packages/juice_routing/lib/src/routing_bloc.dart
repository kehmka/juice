import 'package:juice/juice.dart';

import 'path_resolver.dart';
import 'routing_config.dart';
import 'routing_events.dart';
import 'routing_state.dart';
import 'use_cases/initialize_use_case.dart';
import 'use_cases/navigate_use_case.dart';
import 'use_cases/pop_to_root_use_case.dart';
import 'use_cases/pop_until_use_case.dart';
import 'use_cases/pop_use_case.dart';
import 'use_cases/reset_stack_use_case.dart';
import 'use_cases/visibility_use_cases.dart';

/// Bloc for managing declarative, state-driven navigation.
///
/// [RoutingBloc] is the central navigation controller that manages the
/// route stack, handles guards, and integrates with Navigator 2.0.
///
/// ## Usage
///
/// ```dart
/// // Register with BlocScope
/// BlocScope.register<RoutingBloc>(
///   () => RoutingBloc(),
///   lifecycle: BlocLifecycle.permanent,
/// );
///
/// // Get instance and initialize
/// final routingBloc = BlocScope.get<RoutingBloc>();
/// routingBloc.send(InitializeRoutingEvent(config: routingConfig));
///
/// // Navigate
/// routingBloc.navigate('/profile/123');
/// routingBloc.pop();
/// ```
///
/// ## Contract Guarantees
///
/// - **Atomicity**: Navigation either commits fully or not at all
/// - **Concurrency**: One pending navigation; new ones queue (latest wins)
/// - **Redirect cap**: Max 5 redirects before [RedirectLoopError]
/// - **Guard errors**: Exception → [GuardExceptionError], navigation aborted
/// - **Pop behavior**: Pop events bypass guards, execute immediately
class RoutingBloc extends JuiceBloc<RoutingState> {
  late RoutingConfig _config;
  late PathResolver _pathResolver;
  NavigateEvent? _queuedNavigation;

  RoutingBloc()
      : super(
          RoutingState.initial,
          [
            () => UseCaseBuilder(
                  typeOfEvent: InitializeRoutingEvent,
                  useCaseGenerator: () => InitializeUseCase(),
                ),
            () => UseCaseBuilder(
                  typeOfEvent: NavigateEvent,
                  useCaseGenerator: () => NavigateUseCase(),
                ),
            () => UseCaseBuilder(
                  typeOfEvent: PopEvent,
                  useCaseGenerator: () => PopUseCase(),
                ),
            () => UseCaseBuilder(
                  typeOfEvent: PopUntilEvent,
                  useCaseGenerator: () => PopUntilUseCase(),
                ),
            () => UseCaseBuilder(
                  typeOfEvent: PopToRootEvent,
                  useCaseGenerator: () => PopToRootUseCase(),
                ),
            () => UseCaseBuilder(
                  typeOfEvent: ResetStackEvent,
                  useCaseGenerator: () => ResetStackUseCase(),
                ),
            () => UseCaseBuilder(
                  typeOfEvent: RouteVisibleEvent,
                  useCaseGenerator: () => RouteVisibleUseCase(),
                ),
            () => UseCaseBuilder(
                  typeOfEvent: RouteHiddenEvent,
                  useCaseGenerator: () => RouteHiddenUseCase(),
                ),
          ],
        );

  /// Factory constructor that initializes with a config.
  ///
  /// Equivalent to creating a RoutingBloc and sending InitializeRoutingEvent.
  factory RoutingBloc.withConfig(RoutingConfig config, {String? initialPath}) {
    final bloc = RoutingBloc();
    bloc.send(InitializeRoutingEvent(config: config, initialPath: initialPath));
    return bloc;
  }

  /// The routing configuration. Only valid after initialization.
  RoutingConfig get config => _config;

  /// The path resolver. Only valid after initialization.
  PathResolver get pathResolver => _pathResolver;

  /// Set config and resolver during initialization.
  void setConfig(RoutingConfig config, PathResolver resolver) {
    _config = config;
    _pathResolver = resolver;
  }

  /// Queue a navigation event (for when already navigating).
  void queueNavigation(NavigateEvent event) {
    _queuedNavigation = event;
  }

  /// Dequeue and return any queued navigation.
  NavigateEvent? dequeueNavigation() {
    final queued = _queuedNavigation;
    _queuedNavigation = null;
    return queued;
  }

  // Convenience methods

  /// Navigate to a path.
  ///
  /// Shorthand for `send(NavigateEvent(path: path))`.
  void navigate(String path, {Object? extra, bool replace = false}) {
    send(NavigateEvent(path: path, extra: extra, replace: replace));
  }

  /// Pop the current route.
  ///
  /// Shorthand for `send(PopEvent())`.
  void pop({Object? result}) {
    send(PopEvent(result: result));
  }

  /// Pop routes until a condition is met.
  ///
  /// Shorthand for `send(PopUntilEvent(predicate: predicate))`.
  void popUntil(bool Function(StackEntry entry) predicate) {
    send(PopUntilEvent(predicate: predicate));
  }

  /// Pop all routes except the root.
  ///
  /// Shorthand for `send(PopToRootEvent())`.
  void popToRoot() {
    send(PopToRootEvent());
  }

  /// Reset the stack to a single route.
  ///
  /// Shorthand for `send(ResetStackEvent(path: path))`.
  void resetStack(String path, {Object? extra}) {
    send(ResetStackEvent(path: path, extra: extra));
  }
}
