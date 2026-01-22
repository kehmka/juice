import 'package:flutter/foundation.dart';

/// Route transition animation types
enum RouteTransition {
  /// Platform default (Cupertino on iOS, Material on Android)
  platform,

  /// No animation
  none,

  /// Fade in/out
  fade,

  /// Slide from right
  slideRight,

  /// Slide from bottom
  slideBottom,

  /// Scale from center
  scale,

  /// Custom (provide pageBuilder in RouteConfig)
  custom,
}

/// Type of navigation action for history tracking
enum NavigationType {
  /// New route pushed onto stack
  push,

  /// Route popped from stack
  pop,

  /// Top route replaced
  replace,

  /// Stack reset to single route
  reset,
}

/// Entry in navigation history
@immutable
class HistoryEntry {
  /// The path that was navigated to
  final String path;

  /// When this navigation occurred
  final DateTime timestamp;

  /// Type of navigation action
  final NavigationType type;

  /// Time spent on this route (set when route is left)
  final Duration? timeOnRoute;

  const HistoryEntry({
    required this.path,
    required this.timestamp,
    required this.type,
    this.timeOnRoute,
  });

  HistoryEntry copyWith({
    String? path,
    DateTime? timestamp,
    NavigationType? type,
    Duration? timeOnRoute,
  }) {
    return HistoryEntry(
      path: path ?? this.path,
      timestamp: timestamp ?? this.timestamp,
      type: type ?? this.type,
      timeOnRoute: timeOnRoute ?? this.timeOnRoute,
    );
  }

  @override
  String toString() => 'HistoryEntry($type: $path)';
}

/// Tracks pending navigation state during guard execution
@immutable
class PendingNavigation {
  /// Target path being navigated to
  final String targetPath;

  /// Number of guards that have completed
  final int guardsCompleted;

  /// Total number of guards to run
  final int totalGuards;

  /// Current guard being executed (for UI feedback)
  final String? currentGuardName;

  /// Number of redirects in current chain (for loop detection)
  final int redirectCount;

  const PendingNavigation({
    required this.targetPath,
    required this.guardsCompleted,
    required this.totalGuards,
    this.currentGuardName,
    this.redirectCount = 0,
  });

  PendingNavigation copyWith({
    String? targetPath,
    int? guardsCompleted,
    int? totalGuards,
    String? currentGuardName,
    int? redirectCount,
  }) {
    return PendingNavigation(
      targetPath: targetPath ?? this.targetPath,
      guardsCompleted: guardsCompleted ?? this.guardsCompleted,
      totalGuards: totalGuards ?? this.totalGuards,
      currentGuardName: currentGuardName ?? this.currentGuardName,
      redirectCount: redirectCount ?? this.redirectCount,
    );
  }

  @override
  String toString() =>
      'PendingNavigation($targetPath, $guardsCompleted/$totalGuards)';
}

// Counter for generating unique entry keys
int _entryKeyCounter = 0;

/// Generate a unique key for a stack entry
String generateEntryKey() {
  _entryKeyCounter++;
  return 'entry_${DateTime.now().microsecondsSinceEpoch}_$_entryKeyCounter';
}
