import 'dart:convert';

import 'package:juice/juice.dart';
import 'package:juice_storage/juice_storage.dart';

import 'auth_config.dart';
import 'auth_credentials.dart';
import 'auth_events.dart';
import 'auth_result.dart';
import 'auth_state.dart';
import 'auth_user.dart';
import 'use_cases/login_use_case.dart';
import 'use_cases/logout_use_case.dart';
import 'use_cases/refresh_token_use_case.dart';
import 'use_cases/restore_session_use_case.dart';
import 'use_cases/update_user_use_case.dart';
import 'use_cases/token_expiry_use_case.dart';

/// Primary bloc for authentication lifecycle management.
///
/// AuthBloc owns the authentication state: login, logout, token refresh,
/// session restore, and session expiry detection. It delegates provider-specific
/// logic to [AuthProvider] implementations.
///
/// ```dart
/// BlocScope.register<AuthBloc>(
///   () => AuthBloc(storageBloc: BlocScope.get<StorageBloc>()),
///   lifecycle: BlocLifecycle.permanent,
/// );
///
/// // Initialize with config
/// final authBloc = BlocScope.get<AuthBloc>();
/// authBloc.send(InitializeAuthEvent(config: authConfig));
///
/// // Or use the factory constructor
/// BlocScope.register<AuthBloc>(
///   () => AuthBloc.withConfig(
///     AuthConfig(providers: {'email': MyAuthProvider()}),
///     storageBloc: BlocScope.get<StorageBloc>(),
///   ),
///   lifecycle: BlocLifecycle.permanent,
/// );
/// ```
class AuthBloc extends JuiceBloc<AuthState> {
  late AuthConfig _config;
  final StorageBloc storageBloc;
  Timer? _refreshTimer;

  /// Singleflight completer — prevents concurrent refresh attempts.
  ///
  /// Shared across use cases via `bloc.refreshInFlight`.
  Completer<String?>? refreshInFlight;

  AuthBloc({required this.storageBloc})
      : super(
          AuthState.initial,
          [
            () => UseCaseBuilder(
                  typeOfEvent: InitializeAuthEvent,
                  useCaseGenerator: () => RestoreSessionUseCase(),
                ),
            () => UseCaseBuilder(
                  typeOfEvent: LoginEvent,
                  useCaseGenerator: () => LoginUseCase(),
                ),
            () => UseCaseBuilder(
                  typeOfEvent: LogoutEvent,
                  useCaseGenerator: () => LogoutUseCase(),
                ),
            () => UseCaseBuilder(
                  typeOfEvent: RefreshTokenEvent,
                  useCaseGenerator: () => RefreshTokenUseCase(),
                ),
            () => UseCaseBuilder(
                  typeOfEvent: UpdateUserEvent,
                  useCaseGenerator: () => UpdateUserUseCase(),
                ),
            () => UseCaseBuilder(
                  typeOfEvent: TokenExpiryEvent,
                  useCaseGenerator: () => TokenExpiryUseCase(),
                ),
          ],
        );

  /// Factory constructor that initializes with a config.
  ///
  /// Equivalent to creating an AuthBloc and sending [InitializeAuthEvent].
  factory AuthBloc.withConfig(
    AuthConfig config, {
    required StorageBloc storageBloc,
  }) {
    final bloc = AuthBloc(storageBloc: storageBloc);
    bloc.send(InitializeAuthEvent(config: config));
    return bloc;
  }

  /// The auth configuration. Only valid after initialization.
  AuthConfig get config => _config;

  /// Set config during initialization.
  void setConfig(AuthConfig config) {
    _config = config;
  }

  // ===========================================================
  // Token Refresh Timer
  // ===========================================================

  /// Schedule a token refresh before expiry.
  void scheduleRefresh(DateTime? expiresAt) {
    cancelRefreshTimer();
    if (expiresAt == null) return;

    final timeUntilRefresh =
        expiresAt.difference(DateTime.now()) - _config.refreshBuffer;

    if (timeUntilRefresh.isNegative) {
      // Already past refresh window — refresh now
      send(TokenExpiryEvent());
      return;
    }

    _refreshTimer = Timer(timeUntilRefresh, () {
      if (!isClosed) {
        send(TokenExpiryEvent());
      }
    });
  }

  /// Cancel the refresh timer.
  void cancelRefreshTimer() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
  }

  // ===========================================================
  // Token Persistence Helpers
  // ===========================================================

  /// Persist tokens and session metadata to secure storage.
  Future<void> persistTokens(String providerName, AuthResult result) async {
    await storageBloc.secureWrite(_config.accessTokenKey, result.accessToken);

    if (result.refreshToken != null && _config.persistRefreshToken) {
      await storageBloc.secureWrite(
          _config.refreshTokenKey, result.refreshToken!);
    }

    await storageBloc.secureWrite(
      _config.sessionKey,
      jsonEncode({
        'providerName': providerName,
        'expiresAt': result.expiresAt?.toIso8601String(),
      }),
    );
  }

  /// Clear all stored tokens from secure storage.
  Future<void> clearStoredTokens() async {
    await storageBloc.secureDelete(_config.accessTokenKey);
    await storageBloc.secureDelete(_config.refreshTokenKey);
    await storageBloc.secureDelete(_config.sessionKey);
    await storageBloc.secureDelete(_config.userKey);
  }

  /// Read stored session metadata from secure storage.
  Future<Map<String, dynamic>?> readStoredSession() async {
    final sessionJson = await storageBloc.secureRead(_config.sessionKey);
    if (sessionJson == null) return null;

    try {
      return jsonDecode(sessionJson) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  /// Read stored refresh token from secure storage.
  Future<String?> readStoredRefreshToken() async {
    return storageBloc.secureRead(_config.refreshTokenKey);
  }

  // ===========================================================
  // Convenience Methods
  // ===========================================================

  /// Login with email and password.
  void loginWithEmail(String email, String password) => send(LoginEvent(
        providerName: 'email',
        credentials: EmailCredentials(email: email, password: password),
      ));

  /// Login with OAuth provider.
  void loginWithOAuth(
    String provider,
    String idToken, {
    String? accessToken,
  }) =>
      send(LoginEvent(
        providerName: provider,
        credentials: OAuthCredentials(
          provider: provider,
          idToken: idToken,
          accessToken: accessToken,
        ),
      ));

  /// Logout (optionally forced).
  void logout({bool force = false}) => send(LogoutEvent(force: force));

  /// Manually refresh the token.
  void refreshToken() => send(RefreshTokenEvent());

  /// Update user profile in state.
  void updateUser(AuthUser user) =>
      send(UpdateUserEvent(updatedUser: user));

  // ===========================================================
  // Lifecycle
  // ===========================================================

  @override
  Future<void> close() async {
    cancelRefreshTimer();

    // Dispose providers (only if config has been set)
    try {
      for (final provider in _config.providers.values) {
        await provider.dispose();
      }
    } catch (_) {
      // Config may not be set if bloc was never initialized
    }

    await super.close();
  }
}
