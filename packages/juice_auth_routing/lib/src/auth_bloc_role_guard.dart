import 'package:juice_auth/juice_auth.dart';
import 'package:juice_routing/juice_routing.dart';

/// A [RoleGuard] wired to [AuthBloc] — blocks routes unless the current user
/// has [roleName] (via `AuthState.hasRole`).
///
/// ```dart
/// RouteConfig('/admin', guards: [AuthBlocRoleGuard(authBloc, 'admin')]);
/// ```
class AuthBlocRoleGuard extends RoleGuard {
  AuthBlocRoleGuard(AuthBloc authBloc, String roleName)
      : super(
          roleName: roleName,
          hasRole: () => authBloc.state.hasRole(roleName),
        );
}
