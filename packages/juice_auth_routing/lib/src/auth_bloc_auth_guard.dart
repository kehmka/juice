import 'package:juice_auth/juice_auth.dart';
import 'package:juice_routing/juice_routing.dart';

import 'session_known.dart';

/// An [AuthGuard] wired to [AuthBloc] — redirects unauthenticated users to
/// [loginPath] (carrying the original target as `returnTo`).
///
/// Evaluated on navigation. To also evict a user whose session ends *while on*
/// a protected route, use [AuthBlocRoutingBridge].
///
/// **It waits for the answer.** While [AuthBloc] is still restoring a stored
/// session its status is `AuthStatus.unknown`, and the guard does not read
/// that as "signed out": it waits until the status is known, then decides.
/// juice_routing runs the guards on the initial path too, so at a cold start
/// the navigation stays pending (show a splash on `state.pending`) for as
/// long as the restore takes, and a signed-in user never sees the login
/// page. A restore that has not answered within [restoreTimeout] throws: the
/// navigation is refused with a `GuardExceptionError` carrying the
/// `TimeoutException`. The guard never falls back to "signed out".
///
/// ```dart
/// RouteConfig('/profile', guards: [AuthBlocAuthGuard(authBloc)]);
/// ```
class AuthBlocAuthGuard extends AuthGuard {
  AuthBlocAuthGuard(
    this.authBloc, {
    super.loginPath,
    this.restoreTimeout = defaultRestoreTimeout,
  }) : super(isAuthenticated: () => authBloc.state.isAuthenticated);

  /// How long the AuthBloc-wired guards wait, unless told otherwise, for a
  /// session restore that is still in flight.
  static const defaultRestoreTimeout = Duration(seconds: 10);

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
