import 'package:juice_auth/juice_auth.dart';

/// Completes once [authBloc] knows whether there is a session: its status
/// has left [AuthStatus.unknown], where it sits from construction until the
/// stored session has been restored (a provider round trip) or found
/// absent. Completes at once when that is already so.
///
/// A guard that answered from the state as it stood would read "not yet
/// known" as "signed out" and send a signed-in user to the login page at
/// every cold start (juice ISSUES #29).
///
/// Fails as [JuiceBloc.waitFor] fails, and the guard lets it: a restore
/// still unanswered after [timeout] throws a `TimeoutException`, a bloc that
/// is closed or closes meanwhile throws a `StateError`. juice_routing turns
/// a throwing guard into a `GuardExceptionError` and refuses the
/// navigation. There is no fallback to "signed out": a guard that cannot
/// tell does not guess.
Future<void> sessionKnown(AuthBloc authBloc, Duration timeout) => authBloc
    .waitFor((state) => state.status != AuthStatus.unknown, timeout: timeout);
