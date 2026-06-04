import 'package:juice/juice.dart';
import 'package:juice_auth/juice_auth.dart';
import 'package:juice_routing/juice_routing.dart';

/// Reactively drives navigation from [AuthBloc] auth transitions.
///
/// Route guards are evaluated *on navigation*, so they don't evict a user whose
/// session ends while they're sitting on a protected route. This bridge watches
/// [AuthBloc] and reacts:
///
/// - **Loses auth** (authenticated → unauthenticated *or* sessionExpired) →
///   `routingBloc.navigate(loginPath, replace: true)`.
/// - **Gains auth** (→ authenticated) → calls [onAuthenticated] (so the app can
///   return to a captured path or go home).
///
/// It owns no state — just a subscription. Call [start] after both blocs exist,
/// and [dispose] to stop.
///
/// ```dart
/// final bridge = AuthBlocRoutingBridge(authBloc, routingBloc)..start();
/// // ... on teardown
/// bridge.dispose();
/// ```
class AuthBlocRoutingBridge {
  final AuthBloc authBloc;
  final RoutingBloc routingBloc;

  /// Where to send a user who loses authentication. Default `/login`.
  final String loginPath;

  /// Called when the user becomes authenticated, with the new auth state.
  final void Function(AuthState state)? onAuthenticated;

  StreamSubscription<StreamStatus<AuthState>>? _subscription;
  bool _wasAuthenticated;

  AuthBlocRoutingBridge(
    this.authBloc,
    this.routingBloc, {
    this.loginPath = '/login',
    this.onAuthenticated,
  }) : _wasAuthenticated = authBloc.state.isAuthenticated;

  /// Begin watching auth transitions.
  void start() {
    _subscription = authBloc.stream.listen((status) {
      final state = status.state;
      final isAuthenticated = state.isAuthenticated;

      if (_wasAuthenticated && !isAuthenticated) {
        // Logout or session expiry while on a (possibly protected) route.
        routingBloc.navigate(loginPath, replace: true);
      } else if (!_wasAuthenticated && isAuthenticated) {
        onAuthenticated?.call(state);
      }

      _wasAuthenticated = isAuthenticated;
    });
  }

  /// Stop watching.
  void dispose() {
    _subscription?.cancel();
    _subscription = null;
  }
}
