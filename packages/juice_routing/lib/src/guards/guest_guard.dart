import '../route_context.dart';
import '../route_guard.dart';

/// Built-in guard that redirects authenticated users away from
/// guest-only pages (e.g., login, register).
///
/// Uses a callback to check authentication state, so it's decoupled from
/// any specific auth implementation.
///
/// Example:
/// ```dart
/// GuestGuard(
///   isAuthenticated: () => authBloc.state.isLoggedIn,
///   redirectPath: '/',  // default
/// )
/// ```
///
/// When the user is already authenticated, the guard redirects to
/// [redirectPath] (typically the home page).
class GuestGuard extends RouteGuard {
  /// Callback that returns `true` when the user is authenticated.
  final bool Function() isAuthenticated;

  /// Path to redirect authenticated users to. Defaults to `'/'`.
  final String redirectPath;

  const GuestGuard({
    required this.isAuthenticated,
    this.redirectPath = '/',
  });

  @override
  String get name => 'GuestGuard';

  @override
  Future<GuardResult> check(RouteContext context) async {
    if (!isAuthenticated()) {
      return const GuardResult.allow();
    }
    return GuardResult.redirect(redirectPath);
  }
}
