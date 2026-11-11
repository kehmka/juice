import 'package:juice_auth/juice_auth.dart';
import 'package:juice_routing/juice_routing.dart';

import 'auth_bloc_auth_guard.dart';
import 'session_known.dart';

/// A [RoleGuard] wired to [AuthBloc] — blocks routes unless the current user
/// has [roleName] (via `AuthState.hasRole`).
///
/// It waits for the answer, as [AuthBlocAuthGuard] does: while a stored
/// session is still being restored there is no user to have a role, and the
/// guard does not read that as "lacks the role"; it waits until the status
/// is known, and refuses the navigation (the guard throws) if that takes
/// longer than [restoreTimeout].
///
/// ```dart
/// RouteConfig('/admin', guards: [AuthBlocRoleGuard(authBloc, 'admin')]);
/// ```
class AuthBlocRoleGuard extends RoleGuard {
  AuthBlocRoleGuard(
    this.authBloc,
    String roleName, {
    this.restoreTimeout = AuthBlocAuthGuard.defaultRestoreTimeout,
  }) : super(
          roleName: roleName,
          hasRole: () => authBloc.state.hasRole(roleName),
        );

  /// The bloc whose session decides.
  final AuthBloc authBloc;

  /// How long to wait for a session restore that is still in flight before
  /// the navigation is refused.
  final Duration restoreTimeout;

  @override
  Future<GuardResult> check(RouteContext context) async {
    await sessionKnown(authBloc, restoreTimeout);
    return super.check(context);
  }
}
