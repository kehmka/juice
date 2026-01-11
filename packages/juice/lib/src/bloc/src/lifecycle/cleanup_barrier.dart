import 'dart:async';
import 'package:flutter/foundation.dart';

/// Result of waiting on cleanup barrier.
@immutable
class CleanupBarrierResult {
  /// All tasks completed before timeout
  final bool completed;

  /// Timeout was reached
  final bool timedOut;

  /// Number of tasks that threw exceptions
  final int failedCount;

  /// Total number of registered tasks
  final int taskCount;

  const CleanupBarrierResult({
    required this.completed,
    required this.timedOut,
    required this.failedCount,
    required this.taskCount,
  });

  /// True if all tasks finished successfully without timeout
  bool get allSucceeded => completed && failedCount == 0;
}

/// Collects cleanup futures from subscribers and awaits them.
///
/// Used during scope lifecycle transitions to coordinate async cleanup.
/// Subscribers register cleanup work via [add], then [wait] awaits
/// all registered work with a configurable timeout.
///
/// Example:
/// ```dart
/// final barrier = CleanupBarrier();
///
/// // Subscribers register cleanup
/// barrier.add(cancelPendingRequests());
/// barrier.add(saveLocalState());
///
/// // Wait for all cleanup with timeout
/// final result = await barrier.wait(timeout: Duration(seconds: 2));
/// if (result.timedOut) {
///   print('Cleanup timed out');
/// }
/// ```
class CleanupBarrier {
  final List<Future<void>> _futures = [];
  bool _closed = false;
  int _failedCount = 0;

  /// Subscribers call this to register cleanup work.
  /// Must be called synchronously when receiving ScopeEndingNotification.
  ///
  /// Returns true if added, false if barrier already closed.
  /// Does NOT throw - late registration is logged but doesn't crash.
  bool add(Future<void> cleanup) {
    if (_closed) {
      // Log via Juice logger if available, but don't crash
      assert(() {
        debugPrint('CleanupBarrier: add() called after close - '
            'cleanup task will not be awaited');
        return true;
      }());
      return false;
    }
    _futures.add(cleanup);
    return true;
  }

  /// Awaits all registered cleanup with timeout.
  ///
  /// Individual task failures are caught and counted, NOT propagated.
  /// This ensures scope disposal always completes deterministically.
  Future<CleanupBarrierResult> wait({
    Duration timeout = const Duration(seconds: 2),
  }) async {
    _closed = true;

    if (_futures.isEmpty) {
      return const CleanupBarrierResult(
        completed: true,
        timedOut: false,
        failedCount: 0,
        taskCount: 0,
      );
    }

    final taskCount = _futures.length;

    // Wrap each future to catch individual failures
    final wrappedFutures = _futures.map((f) async {
      try {
        await f;
      } catch (e, stack) {
        _failedCount++;
        // Log but don't propagate
        assert(() {
          debugPrint('CleanupBarrier: cleanup task failed: $e\n$stack');
          return true;
        }());
      }
    }).toList();

    bool timedOut = false;
    try {
      await Future.wait(wrappedFutures).timeout(timeout);
    } on TimeoutException {
      timedOut = true;
      assert(() {
        debugPrint('CleanupBarrier: timeout after $timeout - '
            '$taskCount tasks may still be running');
        return true;
      }());
    }

    return CleanupBarrierResult(
      completed: !timedOut,
      timedOut: timedOut,
      failedCount: _failedCount,
      taskCount: taskCount,
    );
  }

  /// Number of cleanup tasks currently registered.
  int get pendingCount => _futures.length;

  /// Whether the barrier has been closed (wait() was called).
  bool get isClosed => _closed;
}
