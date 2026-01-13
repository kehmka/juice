import 'dart:async';

/// Function type for navigation execution.
/// Supports both sync and async navigation handlers.
typedef NavigateWhere = FutureOr<void> Function(Map<String, dynamic> args);

/// Function type for creating aviators
typedef AviatorBuilder = AviatorBase Function();

/// Abstract base class for all aviators
abstract class AviatorBase {
  String get name;
  NavigateWhere get navigateWhere;

  /// Cleanup method called when aviator is being disposed
  Future<void> close() async {}
}

/// Basic aviator implementation
class Aviator extends AviatorBase {
  @override
  final String name;

  @override
  final NavigateWhere navigateWhere;

  Aviator({
    required this.name,
    required this.navigateWhere,
  });

  @override
  Future<void> close() async {
    // Basic implementation has no resources to clean up
  }
}
