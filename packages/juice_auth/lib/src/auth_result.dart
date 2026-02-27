import 'package:flutter/foundation.dart';

import 'auth_user.dart';

/// Returned by [AuthProvider] after successful authentication or refresh.
@immutable
class AuthResult {
  /// Access token for API calls.
  final String accessToken;

  /// Refresh token (null if provider doesn't support refresh).
  final String? refreshToken;

  /// When the access token expires (null if unknown).
  final DateTime? expiresAt;

  /// Authenticated user profile.
  final AuthUser user;

  const AuthResult({
    required this.accessToken,
    this.refreshToken,
    this.expiresAt,
    required this.user,
  });
}
