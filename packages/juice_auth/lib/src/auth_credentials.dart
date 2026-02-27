/// Base class for provider-specific credentials.
///
/// Each provider defines its own credential type. AuthBloc passes
/// these to [AuthProvider.authenticate] without inspecting them.
abstract class AuthCredentials {
  const AuthCredentials();
}

/// Email + password credentials.
class EmailCredentials extends AuthCredentials {
  final String email;
  final String password;

  const EmailCredentials({
    required this.email,
    required this.password,
  });
}

/// OAuth credentials (from platform OAuth flow).
///
/// The OAuth flow itself (Google Sign-In, Apple Sign-In) is handled
/// externally. This class carries the resulting tokens to AuthBloc.
class OAuthCredentials extends AuthCredentials {
  /// OAuth provider name (e.g., 'google', 'apple', 'github').
  final String provider;

  /// ID token from the OAuth flow.
  final String idToken;

  /// Access token from the OAuth flow (optional).
  final String? accessToken;

  const OAuthCredentials({
    required this.provider,
    required this.idToken,
    this.accessToken,
  });
}

/// API key credentials (for service-to-service auth).
class ApiKeyCredentials extends AuthCredentials {
  final String apiKey;

  const ApiKeyCredentials({required this.apiKey});
}

/// Biometric unlock credentials (re-auth with stored token).
class BiometricCredentials extends AuthCredentials {
  final String storedRefreshToken;

  const BiometricCredentials({required this.storedRefreshToken});
}
