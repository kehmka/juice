import 'package:juice/juice.dart';

import 'routing_config.dart';
import 'routing_errors.dart';
import 'routing_types.dart';

/// Rebuild groups for efficient UI updates.
///
/// Use these with JuiceWidgetState.groups to subscribe to specific
/// routing state changes.
///
/// Example:
/// ```dart
/// class MyWidget extends StatefulWidget {
///   // ...
/// }
///
/// class _MyWidgetState extends JuiceWidgetState<MyWidget, RoutingBloc, RoutingState> {
///   @override
///   Set<String> get groups => {RoutingGroups.current};
///
///   @override
///   Widget build(BuildContext context) {
///     return Text('Current: ${bloc.state.currentPath}');
///   }
/// }
/// ```
abstract final class RoutingGroups {
  /// The navigation stack changed (push, pop, replace, reset)
  static const String stack = 'routing.stack';

  /// Current route changed
  static const String current = 'routing.current';

  /// Pending navigation state changed (guards running)
  static const String pending = 'routing.pending';

  /// Navigation history changed
  static const String history = 'routing.history';

  /// A routing error occurred
  static const String error = 'routing.error';

  /// All routing groups for full subscription
  static const Set<String> all = {stack, current, pending, history, error};
}

/// An entry in the navigation stack.
///
/// Each navigation creates a new StackEntry with a unique key.
/// Entries track their route configuration, resolved parameters,
/// and timing information.
@immutable
class StackEntry {
  /// The route configuration this entry represents
  final RouteConfig route;

  /// The full matched path (with params resolved)
  final String path;

  /// Path parameters extracted from the URL
  final Map<String, String> params;

  /// Query parameters from the URL
  final Map<String, String> query;

  /// Extra data passed via NavigateEvent
  final Object? extra;

  /// Unique key for this entry (for Navigator reconciliation)
  final String key;

  /// When this entry was pushed onto the stack
  final DateTime pushedAt;

  /// Unique scope identifier for this entry.
  /// Used for ScopeLifecycleBloc integration.
  final String? scopeId;

  const StackEntry({
    required this.route,
    required this.path,
    required this.params,
    required this.query,
    required this.key,
    required this.pushedAt,
    this.extra,
    this.scopeId,
  });

  StackEntry copyWith({
    RouteConfig? route,
    String? path,
    Map<String, String>? params,
    Map<String, String>? query,
    Object? extra,
    String? key,
    DateTime? pushedAt,
    String? scopeId,
  }) {
    return StackEntry(
      route: route ?? this.route,
      path: path ?? this.path,
      params: params ?? this.params,
      query: query ?? this.query,
      extra: extra ?? this.extra,
      key: key ?? this.key,
      pushedAt: pushedAt ?? this.pushedAt,
      scopeId: scopeId ?? this.scopeId,
    );
  }

  @override
  String toString() => 'StackEntry($path, key: $key)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StackEntry &&
          runtimeType == other.runtimeType &&
          key == other.key;

  @override
  int get hashCode => key.hashCode;
}

/// The complete routing state.
///
/// This state is managed by [RoutingBloc] and represents everything
/// about the current navigation state of the application.
@immutable
class RoutingState extends BlocState {
  /// The navigation stack. Bottom of stack is index 0.
  final List<StackEntry> stack;

  /// Pending navigation during guard execution, or null if not navigating.
  final PendingNavigation? pending;

  /// Navigation history for analytics/debugging.
  final List<HistoryEntry> history;

  /// The most recent routing error, or null if no error.
  final RoutingError? error;

  /// Whether the routing system has been initialized.
  final bool isInitialized;

  const RoutingState({
    this.stack = const [],
    this.pending,
    this.history = const [],
    this.error,
    this.isInitialized = false,
  });

  /// The initial state before initialization.
  static const RoutingState initial = RoutingState();

  // Convenience getters

  /// The current (top) stack entry, or null if stack is empty.
  StackEntry? get current => stack.isNotEmpty ? stack.last : null;

  /// The current path, or null if stack is empty.
  String? get currentPath => current?.path;

  /// Whether a navigation is currently in progress.
  bool get isNavigating => pending != null;

  /// Whether the stack can be popped (has more than one entry).
  bool get canPop => stack.length > 1;

  /// Number of entries in the stack.
  int get stackDepth => stack.length;

  RoutingState copyWith({
    List<StackEntry>? stack,
    PendingNavigation? pending,
    bool clearPending = false,
    List<HistoryEntry>? history,
    RoutingError? error,
    bool clearError = false,
    bool? isInitialized,
  }) {
    return RoutingState(
      stack: stack ?? this.stack,
      pending: clearPending ? null : (pending ?? this.pending),
      history: history ?? this.history,
      error: clearError ? null : (error ?? this.error),
      isInitialized: isInitialized ?? this.isInitialized,
    );
  }

  @override
  String toString() => 'RoutingState('
      'stack: ${stack.length}, '
      'current: $currentPath, '
      'pending: ${pending?.targetPath}, '
      'initialized: $isInitialized)';
}
