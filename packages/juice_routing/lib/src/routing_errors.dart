import 'package:flutter/foundation.dart';

/// Base class for all routing errors.
///
/// This is a sealed class hierarchy that represents all possible
/// error conditions during navigation.
@immutable
sealed class RoutingError implements Exception {
  /// Human-readable error message
  final String message;

  const RoutingError(this.message);

  @override
  String toString() => '$runtimeType: $message';
}

/// Thrown when attempting to navigate to a path that doesn't match any route.
final class RouteNotFoundError extends RoutingError {
  /// The path that could not be resolved
  final String path;

  const RouteNotFoundError(this.path)
      : super('No route found for path: $path');
}

/// Thrown when a guard blocks navigation without redirecting.
final class GuardBlockedError extends RoutingError {
  /// The path that was blocked
  final String path;

  /// The guard that blocked navigation
  final String guardName;

  /// Optional reason provided by the guard
  final String? reason;

  const GuardBlockedError({
    required this.path,
    required this.guardName,
    this.reason,
  }) : super(reason != null
            ? 'Navigation to $path blocked by $guardName: $reason'
            : 'Navigation to $path blocked by $guardName');
}

/// Thrown when a guard throws an exception during execution.
final class GuardExceptionError extends RoutingError {
  /// The path being navigated to when the exception occurred
  final String path;

  /// The guard that threw the exception
  final String guardName;

  /// The original exception
  final Object exception;

  /// The stack trace from the original exception
  final StackTrace? stackTrace;

  const GuardExceptionError({
    required this.path,
    required this.guardName,
    required this.exception,
    this.stackTrace,
  }) : super('Guard $guardName threw exception during navigation to $path: $exception');
}

/// Thrown when redirect chain exceeds maximum allowed redirects.
final class RedirectLoopError extends RoutingError {
  /// The redirect chain that was detected
  final List<String> redirectChain;

  /// Maximum redirects allowed
  final int maxRedirects;

  RedirectLoopError({
    required this.redirectChain,
    required this.maxRedirects,
  }) : super('Redirect loop detected after $maxRedirects redirects: '
            '${redirectChain.join(' -> ')}');
}

/// Thrown when a navigation path is malformed.
final class InvalidPathError extends RoutingError {
  /// The invalid path
  final String path;

  /// Specific validation failure reason
  final String reason;

  const InvalidPathError({
    required this.path,
    required this.reason,
  }) : super('Invalid path "$path": $reason');
}

/// Thrown when attempting to pop with only one route on the stack.
final class CannotPopError extends RoutingError {
  CannotPopError() : super('Cannot pop: already at root route');
}
