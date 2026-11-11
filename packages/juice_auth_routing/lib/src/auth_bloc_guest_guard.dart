import 'package:juice_auth/juice_auth.dart';
import 'package:juice_routing/juice_routing.dart';

import 'auth_bloc_auth_guard.dart';
import 'session_known.dart';

/// A [GuestGuard] wired to [AuthBloc] — keeps *authenticated* users out of
/// guest-only routes (login, signup), redirecting them to [redirectPath].
///
/// It waits for the answer, as [AuthBlocAuthGuard] does: while a stored
/// session is still being restored the guard does not treat the user as a
/// guest; it waits until the status is known, and refuses the navigation
/// (the guard throws) if that takes longer than [restoreTimeout].
///
/// ```dart
/// RouteConfig('/login', guards: [AuthBlocGuestGuard(authBloc)]);
/// ```
class AuthBlocGuestGuard extends GuestGuard {
  AuthBlocGuestGuard(
    this.authBloc, {
    super.redirectPath,
    this.restoreTimeout = AuthBlocAuthGuard.defaultRestoreTimeout,
  }) : super(isAuthenticated: () => authBloc.state.isAuthenticated);

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
