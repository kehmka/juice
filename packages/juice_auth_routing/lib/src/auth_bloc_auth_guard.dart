import 'package:juice_auth/juice_auth.dart';
import 'package:juice_routing/juice_routing.dart';

/// An [AuthGuard] wired to [AuthBloc] — redirects unauthenticated users to
/// [loginPath] (carrying the original target as `returnTo`).
///
/// Evaluated on navigation. To also evict a user whose session ends *while on*
/// a protected route, use [AuthBlocRoutingBridge].
///
/// ```dart
/// RouteConfig('/profile', guards: [AuthBlocAuthGuard(authBloc)]);
/// ```
class AuthBlocAuthGuard extends AuthGuard {
  AuthBlocAuthGuard(AuthBloc authBloc, {super.loginPath})
      : super(isAuthenticated: () => authBloc.state.isAuthenticated);
}
