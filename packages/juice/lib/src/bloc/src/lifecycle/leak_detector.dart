import 'package:flutter/foundation.dart';

import '../juice_logger.dart';
import 'lifecycle.dart';

/// Tracks bloc lifecycle events for leak detection in debug mode.
///
/// LeakDetector helps identify:
/// - Unreleased bloc leases (widgets that forget to dispose)
/// - Active blocs at app shutdown
/// - Orphaned subscriptions
///
/// ## Usage
///
/// Enable leak detection in your app's main():
/// ```dart
/// void main() {
///   LeakDetector.enable();
///   runApp(MyApp());
/// }
/// ```
///
/// Check for leaks at shutdown or during testing:
/// ```dart
/// // In tests
/// tearDown(() {
///   LeakDetector.checkForLeaks();
///   BlocScope.reset();
/// });
/// ```
///
/// Get detailed leak report:
/// ```dart
/// if (LeakDetector.hasLeaks) {
///   print(LeakDetector.getLeakReport());
/// }
/// ```
class LeakDetector {
  LeakDetector._();

  static bool _enabled = false;

  /// Whether leak detection is enabled.
  static bool get isEnabled => _enabled;

  /// Tracked lease information.
  static final Map<_LeakKey, _LeakInfo> _trackedLeases = {};

  /// Tracked bloc creations.
  static final Map<BlocId, _BlocCreationInfo> _trackedBlocs = {};

  // ============================================================
  // Configuration
  // ============================================================

  /// Enable leak detection.
  ///
  /// Should be called early in app startup, typically in main().
  /// Only enabled in debug mode (asserts).
  static void enable() {
    assert(() {
      _enabled = true;
      JuiceLoggerConfig.logger.log('Leak detection enabled', context: {
        'type': 'leak_detection',
        'action': 'enable',
      });
      return true;
    }());
  }

  /// Disable leak detection and clear all tracked data.
  static void disable() {
    assert(() {
      _enabled = false;
      _trackedLeases.clear();
      _trackedBlocs.clear();
      return true;
    }());
  }

  // ============================================================
  // Lease Tracking
  // ============================================================

  /// Track when a lease is acquired.
  ///
  /// Called by BlocScope.lease() when leak detection is enabled.
  static void trackLeaseAcquire(BlocId id, {String? context}) {
    if (!_enabled) return;

    assert(() {
      final key = _LeakKey(id, DateTime.now().microsecondsSinceEpoch);
      _trackedLeases[key] = _LeakInfo(
        blocId: id,
        acquiredAt: DateTime.now(),
        stackTrace: StackTrace.current,
        context: context,
      );
      return true;
    }());
  }

  /// Track when a lease is released.
  ///
  /// Called by BlocLease.dispose() when leak detection is enabled.
  static void trackLeaseRelease(BlocId id) {
    if (!_enabled) return;

    assert(() {
      // Remove the oldest unreleased lease for this bloc
      final keysForBloc = _trackedLeases.keys
          .where((k) => k.blocId == id)
          .toList()
        ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

      if (keysForBloc.isNotEmpty) {
        _trackedLeases.remove(keysForBloc.first);
      }
      return true;
    }());
  }

  // ============================================================
  // Bloc Lifecycle Tracking
  // ============================================================

  /// Track when a bloc is created.
  ///
  /// Called by BlocScope when creating a new bloc instance.
  static void trackBlocCreation(BlocId id) {
    if (!_enabled) return;

    assert(() {
      _trackedBlocs[id] = _BlocCreationInfo(
        createdAt: DateTime.now(),
        stackTrace: StackTrace.current,
      );
      return true;
    }());
  }

  /// Track when a bloc is closed.
  ///
  /// Called by BlocScope when closing a bloc instance.
  static void trackBlocClose(BlocId id) {
    if (!_enabled) return;

    assert(() {
      _trackedBlocs.remove(id);
      return true;
    }());
  }

  // ============================================================
  // Leak Detection
  // ============================================================

  /// Check if there are any detected leaks.
  static bool get hasLeaks {
    if (!_enabled) return false;

    return _trackedLeases.isNotEmpty || _trackedBlocs.isNotEmpty;
  }

  /// Get the number of unreleased leases.
  static int get unreleasedLeaseCount => _trackedLeases.length;

  /// Get the number of unclosed blocs.
  static int get unclosedBlocCount => _trackedBlocs.length;

  /// Check for leaks and print warnings.
  ///
  /// Returns true if leaks were found.
  static bool checkForLeaks() {
    if (!_enabled) return false;

    bool leaksFound = false;

    assert(() {
      if (_trackedLeases.isNotEmpty || _trackedBlocs.isNotEmpty) {
        leaksFound = true;
        debugPrint(getLeakReport());
      }
      return true;
    }());

    return leaksFound;
  }

  /// Generate a detailed leak report.
  ///
  /// Returns a formatted string describing all detected leaks
  /// with stack traces for debugging.
  static String getLeakReport() {
    if (!_enabled) return 'Leak detection not enabled';

    final buffer = StringBuffer();
    buffer.writeln('\n=== Juice Leak Detection Report ===\n');

    if (_trackedLeases.isEmpty && _trackedBlocs.isEmpty) {
      buffer.writeln('No leaks detected.');
      return buffer.toString();
    }

    // Report unreleased leases
    if (_trackedLeases.isNotEmpty) {
      buffer.writeln('UNRELEASED LEASES (${_trackedLeases.length}):');
      buffer.writeln('-' * 40);

      final byBloc = <BlocId, List<_LeakInfo>>{};
      for (final entry in _trackedLeases.entries) {
        byBloc.putIfAbsent(entry.key.blocId, () => []).add(entry.value);
      }

      for (final entry in byBloc.entries) {
        buffer.writeln(
          '\n  ${entry.key.type} (${entry.value.length} unreleased):',
        );

        for (final leak in entry.value) {
          buffer.writeln('    Acquired at: ${leak.acquiredAt}');
          if (leak.context != null) {
            buffer.writeln('    Context: ${leak.context}');
          }
          buffer.writeln('    Stack trace:');
          // Only show first few frames for readability
          final frames = leak.stackTrace.toString().split('\n').take(8);
          for (final frame in frames) {
            buffer.writeln('      $frame');
          }
          buffer.writeln();
        }
      }
    }

    // Report unclosed blocs
    if (_trackedBlocs.isNotEmpty) {
      buffer.writeln('\nUNCLOSED BLOCS (${_trackedBlocs.length}):');
      buffer.writeln('-' * 40);

      for (final entry in _trackedBlocs.entries) {
        buffer.writeln('\n  ${entry.key.type}:');
        buffer.writeln('    Created at: ${entry.value.createdAt}');
        buffer.writeln('    Stack trace:');
        final frames = entry.value.stackTrace.toString().split('\n').take(8);
        for (final frame in frames) {
          buffer.writeln('      $frame');
        }
      }
    }

    buffer.writeln('\n=== End Report ===\n');
    return buffer.toString();
  }

  /// Clear all tracked data.
  ///
  /// Useful for resetting between tests.
  @visibleForTesting
  static void reset() {
    assert(() {
      _trackedLeases.clear();
      _trackedBlocs.clear();
      return true;
    }());
  }
}

/// Key for tracking individual leases.
class _LeakKey {
  final BlocId blocId;
  final int timestamp;

  _LeakKey(this.blocId, this.timestamp);

  @override
  bool operator ==(Object other) =>
      other is _LeakKey &&
      blocId == other.blocId &&
      timestamp == other.timestamp;

  @override
  int get hashCode => Object.hash(blocId, timestamp);
}

/// Information about a tracked lease.
class _LeakInfo {
  final BlocId blocId;
  final DateTime acquiredAt;
  final StackTrace stackTrace;
  final String? context;

  _LeakInfo({
    required this.blocId,
    required this.acquiredAt,
    required this.stackTrace,
    this.context,
  });
}

/// Information about a tracked bloc creation.
class _BlocCreationInfo {
  final DateTime createdAt;
  final StackTrace stackTrace;

  _BlocCreationInfo({
    required this.createdAt,
    required this.stackTrace,
  });
}
