import 'package:flutter/foundation.dart';

import 'route_context.dart';

/// Result of a guard check.
///
/// Guards return one of three results:
/// - [AllowResult]: Navigation proceeds to the next guard or commits
/// - [RedirectResult]: Navigation restarts with a new target path
/// - [BlockResult]: Navigation is aborted with an error
@immutable
sealed class GuardResult {
  const GuardResult();

  /// Allow navigation to proceed
  const factory GuardResult.allow() = AllowResult;

  /// Redirect to a different path
  const factory GuardResult.redirect(
    String path, {
    String? returnTo,
  }) = RedirectResult;

  /// Block navigation entirely
  const factory GuardResult.block({String? reason}) = BlockResult;
}

/// Navigation is allowed to proceed.
final class AllowResult extends GuardResult {
  const AllowResult();

  @override
  String toString() => 'GuardResult.allow()';
}

/// Navigation should redirect to a different path.
final class RedirectResult extends GuardResult {
  /// The path to redirect to
  final String path;

  /// Optional return path for post-redirect navigation (e.g., after login)
  final String? returnTo;

  const RedirectResult(this.path, {this.returnTo});

  @override
  String toString() => returnTo != null
      ? 'GuardResult.redirect($path, returnTo: $returnTo)'
      : 'GuardResult.redirect($path)';
}

/// Navigation is blocked.
final class BlockResult extends GuardResult {
  /// Optional reason for blocking
  final String? reason;

  const BlockResult({this.reason});

  @override
  String toString() =>
      reason != null ? 'GuardResult.block($reason)' : 'GuardResult.block()';
}

/// Abstract base class for route guards.
///
/// Guards intercept navigation and can allow, redirect, or block it.
/// Guards run in priority order (lower number = earlier execution).
///
/// Example:
/// ```dart
/// class AuthGuard extends RouteGuard {
///   final bool Function() isAuthenticated;
///
///   AuthGuard({required this.isAuthenticated});
///
///   @override
///   String get name => 'AuthGuard';
///
///   @override
///   Future<GuardResult> check(RouteContext context) async {
///     if (isAuthenticated()) {
///       return const GuardResult.allow();
///     }
///     return GuardResult.redirect('/login', returnTo: context.targetPath);
///   }
/// }
/// ```
abstract class RouteGuard {
  const RouteGuard();

  /// Human-readable name for this guard (used in error messages and logging)
  String get name => runtimeType.toString();

  /// Priority for guard execution order.
  /// Lower numbers execute first. Default is 100.
  int get priority => 100;

  /// Check whether navigation should proceed.
  ///
  /// Returns a [GuardResult] indicating whether to allow, redirect, or block.
  /// This method may be async to support checking remote auth state, etc.
  Future<GuardResult> check(RouteContext context);
}
