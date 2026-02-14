import '../route_context.dart';
import '../route_guard.dart';

/// Built-in guard that redirects unauthenticated users to a login path.
///
/// Uses a callback to check authentication state, so it's decoupled from
/// any specific auth implementation.
///
/// Example:
/// ```dart
/// AuthGuard(
///   isAuthenticated: () => authBloc.state.isLoggedIn,
///   loginPath: '/login',  // default
/// )
/// ```
///
/// When the user is not authenticated, the guard redirects to [loginPath]
/// with the original target path as `returnTo` so the login flow can
/// navigate back after authentication.
class AuthGuard extends RouteGuard {
  /// Callback that returns `true` when the user is authenticated.
  final bool Function() isAuthenticated;

  /// Path to redirect unauthenticated users to. Defaults to `'/login'`.
  final String loginPath;

  const AuthGuard({
    required this.isAuthenticated,
    this.loginPath = '/login',
  });

  @override
  String get name => 'AuthGuard';

  @override
  Future<GuardResult> check(RouteContext context) async {
    if (isAuthenticated()) {
      return const GuardResult.allow();
    }
    return GuardResult.redirect(loginPath, returnTo: context.targetPath);
  }
}
