import 'dart:async';
import 'package:flutter/foundation.dart';
import '../bloc_event.dart';
import 'cleanup_barrier.dart';

/// Base class for events that return typed results.
///
/// Each event instance carries its own [Completer], ensuring concurrent
/// operations never interfere with each other's results.
///
/// Use cases must call [succeed] or [fail] to complete the result.
abstract class ResultEvent<TResult> extends EventBase {
  ResultEvent({super.groupsToRebuild});

  final Completer<TResult> _completer = Completer<TResult>();

  /// The future that completes when the use case finishes.
  Future<TResult> get result => _completer.future;

  /// Whether this event's result has been completed.
  bool get isCompleted => _completer.isCompleted;

  /// Complete the result successfully with [value].
  void succeed(TResult value) {
    if (!_completer.isCompleted) {
      _completer.complete(value);
    }
  }

  /// Complete the result with an error.
  ///
  /// The error will be available when awaiting [result]. If the result
  /// is never awaited, the error is silently ignored to prevent unhandled
  /// exception warnings.
  void fail(Object error, [StackTrace? stackTrace]) {
    if (!_completer.isCompleted) {
      _completer.completeError(error, stackTrace);
      // Ignore unhandled error to prevent zone error handler from firing
      // when the result is never awaited (e.g., in tests).
      _completer.future.ignore();
    }
  }
}

// =============================================================================
// Command Events (sent via bloc.send())
// =============================================================================

/// Event to start tracking a scope.
///
/// Returns the unique scope ID assigned by ScopeBloc.
class StartScopeEvent extends ResultEvent<String> {
  /// Human-readable name for the scope.
  final String name;

  /// Reference to the FeatureScope being tracked.
  /// Using dynamic to avoid circular import with feature_scope.dart
  final dynamic scope;

  StartScopeEvent({
    required this.name,
    required this.scope,
  });
}

/// Event to end a scope (triggers cleanup sequence).
///
/// Returns [EndScopeResult] with cleanup details.
class EndScopeEvent extends ResultEvent<EndScopeResult> {
  /// Scope ID (preferred) - unambiguous, always correct.
  final String? scopeId;

  /// Scope name (legacy convenience) - AMBIGUOUS when multiple scopes
  /// share the same name. When used, returns the first active scope found.
  /// For correctness, always prefer ending by scopeId.
  final String? scopeName;

  EndScopeEvent({this.scopeId, this.scopeName})
      : assert(scopeId != null || scopeName != null,
            'Either scopeId or scopeName must be provided');
}

/// Result of ending a scope.
@immutable
class EndScopeResult {
  /// Whether the scope was found.
  final bool found;

  /// Whether cleanup completed (false if timed out).
  final bool cleanupCompleted;

  /// Number of cleanup tasks that threw exceptions.
  final int cleanupFailedCount;

  /// Duration the scope was active.
  final Duration duration;

  /// Total number of cleanup tasks registered.
  final int cleanupTaskCount;

  const EndScopeResult({
    required this.found,
    required this.cleanupCompleted,
    required this.cleanupFailedCount,
    required this.duration,
    required this.cleanupTaskCount,
  });

  /// Scope ended cleanly with all cleanup succeeded.
  bool get success => found && cleanupCompleted && cleanupFailedCount == 0;

  /// Sentinel for "scope not found" / already ended.
  static const notFound = EndScopeResult(
    found: false,
    cleanupCompleted: true,
    cleanupFailedCount: 0,
    duration: Duration.zero,
    cleanupTaskCount: 0,
  );

  @override
  String toString() => 'EndScopeResult('
      'found: $found, '
      'cleanupCompleted: $cleanupCompleted, '
      'cleanupFailedCount: $cleanupFailedCount, '
      'duration: $duration, '
      'cleanupTaskCount: $cleanupTaskCount)';
}

// =============================================================================
// Notification Events (published via bloc.publish())
// =============================================================================

/// Base class for all scope notifications.
/// Enables type-safe filtering via stream.whereType<T>().
abstract class ScopeNotification {
  /// Unique scope identifier.
  String get scopeId;

  /// Human-readable scope name.
  String get scopeName;
}

/// Notification that a scope has started.
@immutable
class ScopeStartedNotification implements ScopeNotification {
  @override
  final String scopeId;

  @override
  final String scopeName;

  /// When the scope started.
  final DateTime startedAt;

  const ScopeStartedNotification({
    required this.scopeId,
    required this.scopeName,
    required this.startedAt,
  });

  @override
  String toString() => 'ScopeStartedNotification('
      'scopeId: $scopeId, scopeName: $scopeName, startedAt: $startedAt)';
}

/// Notification that a scope is ending - register cleanup NOW.
///
/// Subscribers should synchronously call [barrier.add()] with their
/// cleanup futures when receiving this notification.
@immutable
class ScopeEndingNotification implements ScopeNotification {
  @override
  final String scopeId;

  @override
  final String scopeName;

  /// The cleanup barrier to register cleanup tasks with.
  final CleanupBarrier barrier;

  const ScopeEndingNotification({
    required this.scopeId,
    required this.scopeName,
    required this.barrier,
  });

  @override
  String toString() => 'ScopeEndingNotification('
      'scopeId: $scopeId, scopeName: $scopeName)';
}

/// Notification that a scope has ended - disposal complete.
@immutable
class ScopeEndedNotification implements ScopeNotification {
  @override
  final String scopeId;

  @override
  final String scopeName;

  /// How long the scope was active.
  final Duration duration;

  /// Whether cleanup completed before timeout.
  final bool cleanupCompleted;

  const ScopeEndedNotification({
    required this.scopeId,
    required this.scopeName,
    required this.duration,
    required this.cleanupCompleted,
  });

  @override
  String toString() => 'ScopeEndedNotification('
      'scopeId: $scopeId, scopeName: $scopeName, '
      'duration: $duration, cleanupCompleted: $cleanupCompleted)';
}
