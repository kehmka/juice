import 'package:juice/juice.dart';

import 'crash_reporter.dart';

/// Rebuild groups emitted by `ObservabilityBloc`.
abstract final class ObservabilityGroups {
  /// Counts / enabled / last error changed.
  static const status = 'observability:status';

  static const all = {status};
}

/// Immutable observability state. Holds bookkeeping + the recent breadcrumb ring
/// (the reports themselves go to the reporters).
class ObservabilityState extends BlocState {
  /// Whether errors are captured + reported.
  final bool enabled;

  /// Errors recorded this session.
  final int errorCount;

  /// In-memory breadcrumb ring (most recent last), attached to the next report.
  final List<Breadcrumb> breadcrumbs;

  /// Current user id, if identified.
  final String? userId;

  /// Last recorded error (message), for debugging.
  final String? lastError;

  const ObservabilityState({
    this.enabled = true,
    this.errorCount = 0,
    this.breadcrumbs = const [],
    this.userId,
    this.lastError,
  });

  static const initial = ObservabilityState();

  ObservabilityState copyWith({
    bool? enabled,
    int? errorCount,
    List<Breadcrumb>? breadcrumbs,
    Object? userId = _unset,
    Object? lastError = _unset,
  }) {
    return ObservabilityState(
      enabled: enabled ?? this.enabled,
      errorCount: errorCount ?? this.errorCount,
      breadcrumbs: breadcrumbs ?? this.breadcrumbs,
      userId: identical(userId, _unset) ? this.userId : userId as String?,
      lastError: identical(lastError, _unset) ? this.lastError : lastError as String?,
    );
  }

  @override
  String toString() =>
      'ObservabilityState(enabled: $enabled, errors: $errorCount, crumbs: ${breadcrumbs.length})';
}

const Object _unset = Object();
