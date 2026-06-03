import 'package:juice/juice.dart';
import 'package:juice_auth/juice_auth.dart';
import 'package:juice_network/juice_network.dart';

/// Drives [AuthBloc]'s token refresh and resolves when it completes.
///
/// `juice_network`'s [RefreshTokenInterceptor] expects a
/// `Future<String?> Function()` that triggers a refresh and resolves with the
/// new access token. `AuthBloc.refreshToken()` is fire-and-forget, so this
/// strategy bridges the gap by **watching the bloc's state stream**:
///
/// 1. Snapshot whether a refresh is already in flight.
/// 2. Trigger `AuthBloc.refreshToken()` (its own singleflight collapses
///    concurrent triggers into one provider call).
/// 3. Resolve with the new `accessToken` once `isRefreshing` transitions back
///    to `false`, or with `null` if the session expires (refresh failed).
///
/// Returning `null` (rather than throwing) on failure matches the
/// [RefreshTokenInterceptor] contract: a null token signals refresh-failed, so
/// the original 401 propagates and `onRefreshFailed` fires.
class AuthBlocRefreshStrategy {
  /// The auth bloc whose refresh lifecycle is observed.
  final AuthBloc authBloc;

  /// Maximum time to wait for a refresh to resolve before giving up.
  final Duration timeout;

  const AuthBlocRefreshStrategy(
    this.authBloc, {
    this.timeout = const Duration(seconds: 30),
  });

  /// Trigger a refresh and resolve with the new access token, or `null` on
  /// failure / session expiry / timeout.
  Future<String?> refresh() {
    final completer = Completer<String?>();
    late StreamSubscription<StreamStatus<AuthState>> sub;

    // Seed from the current state so an already-in-flight refresh (started by
    // another caller) is detected even if we miss its isRefreshing:true edge.
    var sawRefreshing = authBloc.state.isRefreshing;

    void finish(String? token) {
      if (completer.isCompleted) return;
      sub.cancel();
      completer.complete(token);
    }

    sub = authBloc.stream.listen((status) {
      final state = status.state;

      // Refresh failed → session expired. Signal failure with null.
      if (state.status == AuthStatus.sessionExpired) {
        finish(null);
        return;
      }

      if (state.isRefreshing) {
        sawRefreshing = true;
      } else if (sawRefreshing) {
        // Refresh cycle completed (true → false). The session now carries the
        // new token (or none, if something cleared it).
        finish(state.session?.accessToken);
      }
    });

    // Trigger after subscribing so we never miss a fast emission.
    authBloc.refreshToken();

    return completer.future.timeout(
      timeout,
      onTimeout: () {
        sub.cancel();
        return null;
      },
    );
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
/// final fetchBloc = FetchBloc(storageBloc: storageBloc, dio: dio);
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
