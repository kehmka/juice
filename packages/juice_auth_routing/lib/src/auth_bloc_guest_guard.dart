import 'package:juice_auth/juice_auth.dart';
import 'package:juice_routing/juice_routing.dart';

/// A [GuestGuard] wired to [AuthBloc] — keeps *authenticated* users out of
/// guest-only routes (login, signup), redirecting them to [redirectPath].
///
/// ```dart
/// RouteConfig('/login', guards: [AuthBlocGuestGuard(authBloc)]);
/// ```
class AuthBlocGuestGuard extends GuestGuard {
  AuthBlocGuestGuard(AuthBloc authBloc, {super.redirectPath})
      : super(isAuthenticated: () => authBloc.state.isAuthenticated);
}
