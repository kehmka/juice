import 'dart:async';
import 'package:flutter/foundation.dart';
import '../juice_bloc.dart';
import '../use_case_builders/use_case_builder.dart';
import 'scope_state.dart';
import 'scope_events.dart';
import 'scope_use_cases.dart';

/// Configuration for LifecycleBloc behavior.
@immutable
class LifecycleBlocConfig {
  /// Default timeout for cleanup operations.
  /// Individual EndScopeEvent can override this.
  final Duration cleanupTimeout;

  /// Called when cleanup times out (for logging/metrics).
  final void Function(String scopeId, String scopeName)? onCleanupTimeout;

  const LifecycleBlocConfig({
    this.cleanupTimeout = const Duration(seconds: 2),
    this.onCleanupTimeout,
  });
}

/// Permanent bloc that tracks active scopes and publishes lifecycle events.
///
/// LifecycleBloc provides reactive lifecycle management for FeatureScopes:
/// - Tracks active scopes by unique ID
/// - Publishes notifications when scopes start, are ending, and have ended
/// - Provides CleanupBarrier for deterministic async cleanup
///
/// ## Registration
///
/// Register as a permanent bloc before any feature scopes:
///
/// ```dart
/// void main() {
///   BlocScope.register<LifecycleBloc>(
///     () => LifecycleBloc(),
///     lifecycle: BlocLifecycle.permanent,
///   );
///   runApp(MyApp());
/// }
/// ```
///
/// ## Subscribing to Scope Lifecycle
///
/// Other blocs can subscribe to scope notifications:
///
/// ```dart
/// class FetchBloc extends JuiceBloc<FetchState> {
///   StreamSubscription? _scopeSubscription;
///
///   FetchBloc() : super(FetchState.initial(), [...]) {
///     if (BlocScope.isRegistered<LifecycleBloc>()) {
///       final lifecycleBloc = BlocScope.get<LifecycleBloc>();
///       _scopeSubscription = lifecycleBloc.notifications
///           .whereType<ScopeEndingNotification>()
///           .listen(_onScopeEnding);
///     }
///   }
///
///   void _onScopeEnding(ScopeEndingNotification notification) {
///     // Register cleanup on the barrier
///     notification.barrier.add(_cancelRequestsForScope(notification.scopeName));
///   }
///
///   @override
///   Future<void> close() async {
///     await _scopeSubscription?.cancel();
///     await super.close();
///   }
/// }
/// ```
class LifecycleBloc extends JuiceBloc<ScopeState> {
  /// Configuration for this bloc.
  final LifecycleBlocConfig config;

  /// Monotonic counter for deterministic, collision-free scope IDs.
  int _nextScopeId = 0;

  /// Notification stream for subscribers (separate from command bus).
  /// Uses sync: true so listeners receive notifications synchronously,
  /// allowing them to add cleanup tasks to barriers before wait() is called.
  final _notifications =
      StreamController<ScopeNotification>.broadcast(sync: true);

  /// In-flight end operations (for idempotency).
  final Map<String, Future<EndScopeResult>> _endingFutures = {};

  /// Creates a LifecycleBloc with optional configuration.
  LifecycleBloc({this.config = const LifecycleBlocConfig()})
      : super(
          const ScopeState(),
          [
            () => UseCaseBuilder(
                  typeOfEvent: StartScopeEvent,
                  useCaseGenerator: () => StartScopeUseCase(),
                ),
            () => UseCaseBuilder(
                  typeOfEvent: EndScopeEvent,
                  useCaseGenerator: () => EndScopeUseCase(),
                ),
          ],
        );

  /// Generate a unique scope ID.
  /// Uses monotonic counter - deterministic and collision-free.
  String generateScopeId() => 'scope_${_nextScopeId++}';

  /// Stream of scope lifecycle notifications.
  ///
  /// Use `whereType<T>()` to filter for specific notification types:
  /// ```dart
  /// notifications.whereType<ScopeEndingNotification>().listen(...)
  /// ```
  Stream<ScopeNotification> get notifications => _notifications.stream;

  /// Publish a notification to subscribers.
  void publish(ScopeNotification notification) {
    if (!_notifications.isClosed) {
      _notifications.add(notification);
    }
  }

  /// Get or create an ending future for idempotent scope end.
  ///
  /// Called by EndScopeUseCase to ensure concurrent end() calls
  /// return the same result.
  ///
  /// If [scopeId] already has an ending future, returns it.
  /// Otherwise, runs [work] and caches the result.
  Future<EndScopeResult> getOrCreateEndingFuture(
    String scopeId,
    Future<EndScopeResult> Function() work,
  ) async {
    // Already ending? Return existing future
    if (_endingFutures.containsKey(scopeId)) {
      return _endingFutures[scopeId]!;
    }

    // Start the end operation
    final completer = Completer<EndScopeResult>();
    _endingFutures[scopeId] = completer.future;

    try {
      final result = await work();
      completer.complete(result);
      return result;
    } catch (e, stack) {
      // Should never happen, but if it does, don't leave orphan future
      completer.completeError(e, stack);
      rethrow;
    } finally {
      _endingFutures.remove(scopeId);
    }
  }

  /// Get in-flight ending future for a scope, if any.
  /// Used when phase==ending to await existing operation.
  Future<EndScopeResult>? getEndingFuture(String scopeId) =>
      _endingFutures[scopeId];

  @override
  Future<void> close() async {
    await _notifications.close();
    await super.close();
  }
}
