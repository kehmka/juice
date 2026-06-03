import 'package:juice_auth/juice_auth.dart';
import 'package:juice_network/juice_network.dart';

/// An [AuthInterceptor] that injects the current access token from [AuthBloc].
///
/// Reads `authBloc.state.session?.accessToken` on each request, so the token is
/// always current — no manual header wiring, no stale tokens after a refresh.
/// When there is no active session the token provider returns `null` and
/// `AuthInterceptor` adds no `Authorization` header.
///
/// ```dart
/// fetchBloc.send(InitializeFetchEvent(
///   config: FetchConfig(baseUrl: 'https://api.example.com'),
///   interceptors: [AuthBlocAuthInterceptor(authBloc)],
/// ));
/// ```
class AuthBlocAuthInterceptor extends AuthInterceptor {
  AuthBlocAuthInterceptor(
    AuthBloc authBloc, {
    super.headerName,
    super.prefix,
    super.skipAuth,
  }) : super(
          tokenProvider: () async => authBloc.state.session?.accessToken,
        );
}
