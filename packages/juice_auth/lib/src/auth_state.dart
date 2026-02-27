import 'package:juice/juice.dart';

import 'auth_errors.dart';
import 'auth_session.dart';
import 'auth_user.dart';

/// Authentication status.
enum AuthStatus {
  /// Initial state — before session restore attempt.
  unknown,

  /// No active session.
  unauthenticated,

  /// Active, valid session.
  authenticated,

  /// Session existed but expired (distinct from [unauthenticated] for UX).
  sessionExpired,
}

/// Rebuild groups for targeted UI updates.
abstract final class AuthGroups {
  /// Auth status changed (login, logout, session expiry).
  static const status = 'auth:status';

  /// User profile changed.
  static const user = 'auth:user';

  /// Session updated (token refresh, expiry change).
  static const session = 'auth:session';

  /// Auth error occurred.
  static const error = 'auth:error';

  /// All auth groups.
  static const Set<String> all = {status, user, session, error};
}

/// Immutable authentication state.
@immutable
class AuthState extends BlocState {
  /// Current authentication status.
  final AuthStatus status;

  /// Authenticated user (null when unauthenticated).
  final AuthUser? user;

  /// Active session (null when unauthenticated).
  final AuthSession? session;

  /// Last auth error (cleared on next successful operation).
  final AuthError? lastError;

  /// Whether a token refresh is currently in progress.
  final bool isRefreshing;

  /// Pending login provider name (during login flow).
  final String? pendingProvider;

  /// Number of failed login attempts in current window.
  final int loginAttempts;

  /// When login attempts will reset (after cooldown).
  final DateTime? loginCooldownUntil;

  const AuthState({
    this.status = AuthStatus.unknown,
    this.user,
    this.session,
    this.lastError,
    this.isRefreshing = false,
    this.pendingProvider,
    this.loginAttempts = 0,
    this.loginCooldownUntil,
  });

  /// Initial state constant.
  static const initial = AuthState();

  /// Whether the user is authenticated.
  bool get isAuthenticated => status == AuthStatus.authenticated;

  /// Whether the session has expired.
  bool get isSessionExpired => status == AuthStatus.sessionExpired;

  /// Shorthand for user ID.
  String? get userId => user?.id;

  /// Shorthand for access token.
  String? get accessToken => session?.accessToken;

  /// Whether the user has a specific role.
  bool hasRole(String role) => user?.roles.contains(role) ?? false;

  /// Whether login is currently rate-limited.
  bool get isRateLimited =>
      loginCooldownUntil != null &&
      DateTime.now().isBefore(loginCooldownUntil!);

  AuthState copyWith({
    AuthStatus? status,
    AuthUser? user,
    AuthSession? session,
    AuthError? lastError,
    bool? isRefreshing,
    String? pendingProvider,
    int? loginAttempts,
    DateTime? loginCooldownUntil,
    bool clearUser = false,
    bool clearSession = false,
    bool clearError = false,
    bool clearPendingProvider = false,
    bool clearCooldown = false,
  }) {
    return AuthState(
      status: status ?? this.status,
      user: clearUser ? null : (user ?? this.user),
      session: clearSession ? null : (session ?? this.session),
      lastError: clearError ? null : (lastError ?? this.lastError),
      isRefreshing: isRefreshing ?? this.isRefreshing,
      pendingProvider: clearPendingProvider
          ? null
          : (pendingProvider ?? this.pendingProvider),
      loginAttempts: loginAttempts ?? this.loginAttempts,
      loginCooldownUntil: clearCooldown
          ? null
          : (loginCooldownUntil ?? this.loginCooldownUntil),
    );
  }

  @override
  String toString() =>
      'AuthState(status: $status, user: ${user?.id}, refreshing: $isRefreshing)';
}
