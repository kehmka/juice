import 'package:juice/juice.dart';
import 'package:juice_auth/juice_auth.dart';
import 'package:juice_network/juice_network.dart';

/// Drives [AuthBloc]'s token refresh and resolves when it completes.
///
/// `juice_network`'s [RefreshTokenInterceptor] expects a
/// `Future<String?> Function()` that triggers a refresh and resolves with the
/// new access token. That is one call: `RefreshTokenEvent` is a result
/// event, so `sendForResult` returns the refreshed session — and it is
/// `singleflight`, so a refresh requested while one is running (by another
/// 401, or by the bloc's own expiry timer) joins it: one provider call, and
/// every caller gets its token.
///
/// Returning `null` (rather than throwing) on failure matches the
/// [RefreshTokenInterceptor] contract: a null token signals refresh-failed, so
/// the original 401 propagates and `onRefreshFailed` fires. Every way a
/// refresh can fail to produce a token is that one signal: no refresh token,
/// the provider refused (the session expired), the bloc is closed or closes
/// meanwhile, or [timeout] ran out. The bloc itself has already said why —
/// in its state (`lastError`) and its telemetry.
class AuthBlocRefreshStrategy {
  /// The auth bloc whose refresh is driven.
  final AuthBloc authBloc;

  /// Maximum time to wait for a refresh to resolve before giving up.
  final Duration timeout;

  const AuthBlocRefreshStrategy(
    this.authBloc, {
    this.timeout = const Duration(seconds: 30),
  });

  /// Trigger a refresh and resolve with the new access token, or `null` on
  /// failure / session expiry / timeout.
  Future<String?> refresh() async {
    try {
      final session =
          await authBloc.sendForResult(RefreshTokenEvent(), timeout: timeout);
      return session.accessToken;
    } catch (_) {
      return null;
    }
  }
}

/// A [RefreshTokenInterceptor] wired to drive [AuthBloc]'s refresh on 401.
///
/// On a refresh-triggering response (401 by default), this interceptor runs
/// [AuthBloc]'s singleflight refresh via [AuthBlocRefreshStrategy], then retries
/// the failed request with the new access token.
///
/// ```dart
/// final dio = Dio();
/// final fetchBloc = FetchBloc(
///   storageBloc: storageBloc,
///   dio: dio,
///   authIdentityProvider: AuthBlocIdentityProvider(authBloc).call,
/// );
/// fetchBloc.send(InitializeFetchEvent(
///   config: FetchConfig(baseUrl: 'https://api.example.com'),
///   interceptors: [
///     AuthBlocAuthInterceptor(authBloc),
///     AuthBlocRefreshInterceptor(authBloc, dio: dio),
///   ],
/// ));
/// ```
class AuthBlocRefreshInterceptor extends RefreshTokenInterceptor {
  AuthBlocRefreshInterceptor(
    AuthBloc authBloc, {
    required super.dio,
    Duration timeout = const Duration(seconds: 30),
    super.onRefreshFailed,
    super.headerName,
    super.prefix,
    super.refreshOnStatusCodes,
  }) : super(
          refreshToken:
              AuthBlocRefreshStrategy(authBloc, timeout: timeout).refresh,
          getAccessToken: () async => authBloc.state.session?.accessToken,
        );
}
