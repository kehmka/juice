import '../fetch_config.dart';
import 'auth_interceptor.dart';
import 'interceptor.dart';

/// Why [interceptors] cannot be installed on a bloc with [provider], or null
/// when they can.
///
/// An [AuthInterceptor] adds the credential inside Dio, after the request key
/// is computed. The key then says nothing about whose response it holds, so
/// the cache and the coalescer would hand one user's response to another.
/// Only an [AuthIdentityProvider] on the bloc puts the user into the key, so
/// an [AuthInterceptor] without one is refused.
String? authIdentityViolation(
  Iterable<FetchInterceptor>? interceptors,
  AuthIdentityProvider? provider,
) {
  if (provider != null || interceptors == null) return null;

  final injecting = interceptors.whereType<AuthInterceptor>().toList();
  if (injecting.isEmpty) return null;

  final names = injecting.map((i) => i.runtimeType).toSet().join(', ');
  return 'FetchBloc was given $names and no authIdentityProvider. '
      'Credentials added by an interceptor are not part of the cache and '
      'coalescing key, so responses would be shared between users. '
      'Pass authIdentityProvider to FetchBloc: the signed-in user\'s id, '
      'or null when signed out.';
}
