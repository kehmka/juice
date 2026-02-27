import 'package:flutter/foundation.dart';

import 'auth_provider.dart';

/// Configuration for [AuthBloc].
@immutable
class AuthConfig {
  /// Registered auth providers (at least one required).
  ///
  /// Keyed by provider name (e.g., 'email', 'google').
  final Map<String, AuthProvider> providers;

  /// Trigger refresh this long before token expiry.
  ///
  /// Default: 60 seconds before expiry.
  final Duration refreshBuffer;

  /// Whether to attempt session restore on initialization.
  ///
  /// Default: true.
  final bool restoreSessionOnInit;

  /// Secure storage key prefix (for multi-app isolation).
  ///
  /// Default: 'juice_auth'.
  final String storagePrefix;

  /// Maximum login attempts before cooldown.
  ///
  /// Default: 5.
  final int maxLoginAttempts;

  /// Cooldown duration after max login attempts.
  ///
  /// Default: 30 seconds.
  final Duration loginCooldown;

  /// Whether to persist the refresh token to secure storage.
  ///
  /// Default: true.
  final bool persistRefreshToken;

  /// Secure storage key for access token.
  String get accessTokenKey => '${storagePrefix}_access_token';

  /// Secure storage key for refresh token.
  String get refreshTokenKey => '${storagePrefix}_refresh_token';

  /// Secure storage key for session metadata.
  String get sessionKey => '${storagePrefix}_session';

  /// Secure storage key for user data.
  String get userKey => '${storagePrefix}_user';

  const AuthConfig({
    required this.providers,
    this.refreshBuffer = const Duration(seconds: 60),
    this.restoreSessionOnInit = true,
    this.storagePrefix = 'juice_auth',
    this.maxLoginAttempts = 5,
    this.loginCooldown = const Duration(seconds: 30),
    this.persistRefreshToken = true,
  });
}
