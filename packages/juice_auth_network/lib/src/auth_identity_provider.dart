import 'package:juice_auth/juice_auth.dart';
import 'package:juice_network/juice_network.dart';

/// Bridges [AuthBloc] to `juice_network`'s [AuthIdentityProvider].
///
/// `FetchBloc` uses the returned identity to isolate cache and coalescing
/// entries per user, so one user's cached responses never leak to another
/// after a logout/login on the same device.
///
/// The identity is the authenticated user's id, or `null` when there is no
/// authenticated user (in which case `FetchBloc` falls back to its
/// unscoped/shared behavior).
///
/// ```dart
/// final fetchBloc = FetchBloc(
///   storageBloc: storageBloc,
///   authIdentityProvider: AuthBlocIdentityProvider(authBloc).call,
/// );
/// ```
class AuthBlocIdentityProvider {
  /// The auth bloc whose current user identifies the cache scope.
  final AuthBloc authBloc;

  const AuthBlocIdentityProvider(this.authBloc);

  /// Returns the current user id, or `null` when unauthenticated.
  ///
  /// Matches the [AuthIdentityProvider] signature (`String? Function()`), so it
  /// can be passed directly as `authIdentityProvider: provider.call`.
  String? call() => authBloc.state.userId;
}
