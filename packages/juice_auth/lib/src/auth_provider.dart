import 'auth_credentials.dart';
import 'auth_result.dart';
import 'auth_session.dart';
import 'auth_user.dart';

/// Contract that any auth backend must implement.
///
/// AuthBloc delegates all provider-specific logic to this interface.
/// Implement this for your backend (REST API, Firebase, Supabase, etc.).
///
/// ```dart
/// class MyApiAuthProvider extends AuthProvider {
///   @override
///   String get name => 'email';
///
///   @override
///   Future<AuthResult> authenticate(AuthCredentials credentials) async {
///     final creds = credentials as EmailCredentials;
///     final response = await api.login(creds.email, creds.password);
///     return AuthResult(
///       accessToken: response.accessToken,
///       refreshToken: response.refreshToken,
///       expiresAt: response.expiresAt,
///       user: AuthUser(id: response.userId, email: creds.email),
///     );
///   }
///   // ...
/// }
/// ```
abstract class AuthProvider {
  /// Human-readable provider name (e.g., 'email', 'google', 'apple').
  String get name;

  /// Authenticate with provider-specific credentials.
  ///
  /// Returns [AuthResult] with tokens and user info.
  /// Throws [AuthProviderException] on failure.
  Future<AuthResult> authenticate(AuthCredentials credentials);

  /// Refresh the access token using the refresh token.
  ///
  /// Returns new [AuthResult] with updated tokens.
  /// Throws [AuthProviderException] if refresh fails (session invalid).
  Future<AuthResult> refreshToken(String refreshToken);

  /// Revoke the session (best-effort, for logout).
  ///
  /// Should not throw — failures are logged, not propagated.
  Future<void> revokeSession(AuthSession session);

  /// Fetch fresh user profile from provider (optional).
  ///
  /// Used for periodic profile sync.
  Future<AuthUser?> fetchUser(String accessToken) async => null;

  /// Whether this provider supports token refresh.
  bool get supportsRefresh => true;

  /// Dispose provider resources.
  Future<void> dispose() async {}
}

/// Exception thrown by [AuthProvider] implementations.
///
/// Wraps provider-specific errors into a common type that AuthBloc
/// can handle uniformly.
class AuthProviderException implements Exception {
  /// Human-readable error message.
  final String message;

  /// Provider-specific error code (e.g., 'INVALID_PASSWORD').
  final String? code;

  /// Original error from the provider SDK.
  final dynamic originalError;

  const AuthProviderException(
    this.message, {
    this.code,
    this.originalError,
  });

  @override
  String toString() => 'AuthProviderException: $message (code: $code)';
}
