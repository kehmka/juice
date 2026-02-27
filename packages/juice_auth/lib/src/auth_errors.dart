import 'package:flutter/foundation.dart';

/// Base class for auth errors.
///
/// Sealed hierarchy — exhaustive switch in error handling.
@immutable
sealed class AuthError implements Exception {
  String get message;

  @override
  String toString() => '$runtimeType: $message';
}

/// Provider returned an error (wrong password, account locked, etc.).
final class ProviderAuthError extends AuthError {
  final String providerName;
  @override
  final String message;

  ProviderAuthError(this.message, {required this.providerName});
}

/// Unknown provider name in [LoginEvent].
final class UnknownProviderError extends AuthError {
  final String providerName;

  UnknownProviderError(this.providerName);

  @override
  String get message => 'Unknown auth provider: $providerName';
}

/// Token refresh failed.
final class RefreshFailedError extends AuthError {
  final String reason;

  RefreshFailedError(this.reason);

  @override
  String get message => 'Token refresh failed: $reason';
}

/// No refresh token available to refresh with.
final class NoRefreshTokenError extends AuthError {
  @override
  String get message => 'No refresh token available';
}

/// Too many login attempts — rate limited.
final class RateLimitedError extends AuthError {
  final Duration cooldown;

  RateLimitedError(this.cooldown);

  @override
  String get message =>
      'Too many login attempts. Try again in ${cooldown.inSeconds}s';
}

/// Secure storage operation failed.
final class StorageAuthError extends AuthError {
  final String operation;
  final String reason;

  StorageAuthError(this.operation, this.reason);

  @override
  String get message => 'Auth storage $operation failed: $reason';
}

/// Session restore failed.
final class RestoreFailedError extends AuthError {
  final String reason;

  RestoreFailedError(this.reason);

  @override
  String get message => 'Session restore failed: $reason';
}
