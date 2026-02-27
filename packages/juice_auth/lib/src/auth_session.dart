import 'package:flutter/foundation.dart';

/// Represents an active authentication session.
@immutable
class AuthSession {
  /// Access token for API calls.
  final String accessToken;

  /// Refresh token (null if provider doesn't support refresh).
  final String? refreshToken;

  /// When the access token expires (null if unknown).
  final DateTime? expiresAt;

  /// Which provider created this session.
  final String providerName;

  /// When the session was created.
  final DateTime createdAt;

  /// When the token was last refreshed.
  final DateTime? lastRefreshedAt;

  const AuthSession({
    required this.accessToken,
    this.refreshToken,
    this.expiresAt,
    required this.providerName,
    required this.createdAt,
    this.lastRefreshedAt,
  });

  /// Whether the access token is expired.
  bool get isExpired =>
      expiresAt?.isBefore(DateTime.now()) ?? false;

  /// Time until the access token expires (null if expiry unknown).
  Duration? get timeUntilExpiry =>
      expiresAt?.difference(DateTime.now());

  AuthSession copyWith({
    String? accessToken,
    String? refreshToken,
    DateTime? expiresAt,
    String? providerName,
    DateTime? createdAt,
    DateTime? lastRefreshedAt,
  }) {
    return AuthSession(
      accessToken: accessToken ?? this.accessToken,
      refreshToken: refreshToken ?? this.refreshToken,
      expiresAt: expiresAt ?? this.expiresAt,
      providerName: providerName ?? this.providerName,
      createdAt: createdAt ?? this.createdAt,
      lastRefreshedAt: lastRefreshedAt ?? this.lastRefreshedAt,
    );
  }

  @override
  String toString() =>
      'AuthSession(provider: $providerName, expiresAt: $expiresAt)';
}
