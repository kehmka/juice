import 'package:juice/juice.dart';

import 'auth_credentials.dart';
import 'auth_config.dart';
import 'auth_user.dart';

/// Base class for all auth events.
abstract class AuthEvent extends EventBase {
  AuthEvent({super.groupsToRebuild});

  @override
  String toString() => runtimeType.toString();
}

/// Initialize AuthBloc with configuration.
///
/// Triggers session restore if [AuthConfig.restoreSessionOnInit] is true.
class InitializeAuthEvent extends AuthEvent {
  final AuthConfig config;
  InitializeAuthEvent({required this.config});

  @override
  String toString() => 'InitializeAuthEvent(restore: ${config.restoreSessionOnInit})';
}

/// Login with a specific provider and credentials.
class LoginEvent extends AuthEvent {
  /// Provider name (must match a key in [AuthConfig.providers]).
  final String providerName;

  /// Provider-specific credentials.
  final AuthCredentials credentials;

  LoginEvent({
    required this.providerName,
    required this.credentials,
    super.groupsToRebuild,
  });

  @override
  String toString() => 'LoginEvent(provider: $providerName)';
}

/// Logout and clear all session data.
class LogoutEvent extends AuthEvent {
  /// If true, skip provider revocation (for forced logout on refresh failure).
  final bool force;
  LogoutEvent({this.force = false, super.groupsToRebuild});

  @override
  String toString() => 'LogoutEvent(force: $force)';
}

/// Manually trigger a token refresh.
///
/// Usually not needed — AuthBloc refreshes proactively before expiry.
class RefreshTokenEvent extends AuthEvent {
  @override
  String toString() => 'RefreshTokenEvent()';
}

/// Update user profile in state (after profile edit, etc.).
class UpdateUserEvent extends AuthEvent {
  final AuthUser updatedUser;
  UpdateUserEvent({required this.updatedUser, super.groupsToRebuild});

  @override
  String toString() => 'UpdateUserEvent(user: ${updatedUser.id})';
}

/// Internal: emitted when the refresh timer fires before token expiry.
class TokenExpiryEvent extends AuthEvent {
  @override
  String toString() => 'TokenExpiryEvent()';
}
