import 'bloc_lifecycle.dart';

/// Diagnostic information about a registered bloc.
///
/// Use [BlocScope.diagnostics] to retrieve this information
/// for debugging and monitoring.
class BlocDiagnostics {
  const BlocDiagnostics({
    required this.type,
    required this.scope,
    required this.lifecycle,
    required this.isActive,
    required this.leaseCount,
    required this.isClosing,
    required this.createdAt,
  });

  /// The bloc type.
  final Type type;

  /// The scope key, or null for global scope.
  final Object? scope;

  /// The lifecycle behavior.
  final BlocLifecycle lifecycle;

  /// Whether the bloc instance is active.
  final bool isActive;

  /// Number of active leases.
  final int leaseCount;

  /// Whether the bloc is currently being closed.
  final bool isClosing;

  /// When the instance was created, if active.
  final DateTime? createdAt;

  @override
  String toString() => 'BlocDiagnostics('
      'type: $type, '
      'scope: $scope, '
      'lifecycle: $lifecycle, '
      'isActive: $isActive, '
      'leaseCount: $leaseCount, '
      'isClosing: $isClosing, '
      'createdAt: $createdAt)';
}
