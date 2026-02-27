import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:juice_auth/juice_auth.dart';
import 'package:juice_storage/juice_storage.dart';
import 'package:mocktail/mocktail.dart';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class MockStorageBloc extends Mock implements StorageBloc {}

class MockAuthProvider extends Mock implements AuthProvider {}

class FakeAuthCredentials extends Fake implements AuthCredentials {}

class FakeAuthSession extends Fake implements AuthSession {}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const _delay = Duration(milliseconds: 50);

AuthResult _makeResult({
  String accessToken = 'access-token',
  String? refreshToken = 'refresh-token',
  DateTime? expiresAt,
  String userId = 'user-1',
  String? email = 'test@example.com',
}) =>
    AuthResult(
      accessToken: accessToken,
      refreshToken: refreshToken,
      expiresAt: expiresAt,
      user: AuthUser(id: userId, email: email),
    );

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // ======== Model / value-object tests (unchanged) ========

  group('AuthState', () {
    test('default state is unknown', () {
      const state = AuthState();
      expect(state.status, AuthStatus.unknown);
      expect(state.isAuthenticated, false);
      expect(state.user, isNull);
      expect(state.session, isNull);
    });

    test('initial constant matches default constructor', () {
      expect(AuthState.initial.status, AuthStatus.unknown);
      expect(AuthState.initial.isAuthenticated, false);
    });

    test('isAuthenticated returns true when status is authenticated', () {
      const state = AuthState(status: AuthStatus.authenticated);
      expect(state.isAuthenticated, true);
    });

    test('isSessionExpired returns true when status is sessionExpired', () {
      const state = AuthState(status: AuthStatus.sessionExpired);
      expect(state.isSessionExpired, true);
      expect(state.isAuthenticated, false);
    });

    test('copyWith preserves values', () {
      final state = AuthState(
        status: AuthStatus.authenticated,
        user: const AuthUser(id: 'user-1', email: 'test@example.com'),
        session: AuthSession(
          accessToken: 'token',
          providerName: 'email',
          createdAt: DateTime(2026, 1, 1),
        ),
      );

      final copied = state.copyWith(isRefreshing: true);
      expect(copied.status, AuthStatus.authenticated);
      expect(copied.user?.id, 'user-1');
      expect(copied.isRefreshing, true);
    });

    test('copyWith clear flags reset values to null', () {
      final state = AuthState(
        status: AuthStatus.authenticated,
        user: const AuthUser(id: 'user-1'),
        session: AuthSession(
          accessToken: 'token',
          providerName: 'email',
          createdAt: DateTime(2026, 1, 1),
        ),
        pendingProvider: 'email',
      );

      final cleared = state.copyWith(
        clearUser: true,
        clearSession: true,
        clearPendingProvider: true,
      );
      expect(cleared.user, isNull);
      expect(cleared.session, isNull);
      expect(cleared.pendingProvider, isNull);
      expect(cleared.status, AuthStatus.authenticated);
    });

    test('hasRole checks user roles', () {
      const state = AuthState(
        status: AuthStatus.authenticated,
        user: AuthUser(id: 'user-1', roles: {'admin', 'editor'}),
      );
      expect(state.hasRole('admin'), true);
      expect(state.hasRole('editor'), true);
      expect(state.hasRole('viewer'), false);
    });

    test('hasRole returns false when no user', () {
      const state = AuthState(status: AuthStatus.unauthenticated);
      expect(state.hasRole('admin'), false);
    });

    test('isRateLimited checks cooldown', () {
      final state = AuthState(
        loginCooldownUntil: DateTime.now().add(const Duration(seconds: 30)),
      );
      expect(state.isRateLimited, true);

      final expired = AuthState(
        loginCooldownUntil:
            DateTime.now().subtract(const Duration(seconds: 1)),
      );
      expect(expired.isRateLimited, false);
    });

    test('toString includes status and user', () {
      const state = AuthState(
        status: AuthStatus.authenticated,
        user: AuthUser(id: 'u1'),
      );
      expect(state.toString(), contains('authenticated'));
      expect(state.toString(), contains('u1'));
    });
  });

  group('AuthGroups', () {
    test('all contains every group', () {
      expect(AuthGroups.all, contains(AuthGroups.status));
      expect(AuthGroups.all, contains(AuthGroups.user));
      expect(AuthGroups.all, contains(AuthGroups.session));
      expect(AuthGroups.all, contains(AuthGroups.error));
      expect(AuthGroups.all.length, 4);
    });
  });

  group('AuthUser', () {
    test('equality based on id', () {
      const user1 = AuthUser(id: 'user-1', email: 'a@test.com');
      const user2 = AuthUser(id: 'user-1', email: 'b@test.com');
      const user3 = AuthUser(id: 'user-2', email: 'a@test.com');

      expect(user1, equals(user2));
      expect(user1, isNot(equals(user3)));
    });

    test('copyWith updates fields', () {
      const user = AuthUser(id: 'user-1', displayName: 'Alice');
      final updated = user.copyWith(displayName: 'Bob');
      expect(updated.id, 'user-1');
      expect(updated.displayName, 'Bob');
    });
  });

  group('AuthSession', () {
    test('isExpired checks expiresAt', () {
      final expired = AuthSession(
        accessToken: 'token',
        providerName: 'email',
        createdAt: DateTime(2026, 1, 1),
        expiresAt: DateTime.now().subtract(const Duration(hours: 1)),
      );
      expect(expired.isExpired, true);

      final valid = AuthSession(
        accessToken: 'token',
        providerName: 'email',
        createdAt: DateTime(2026, 1, 1),
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      );
      expect(valid.isExpired, false);
    });

    test('isExpired returns false when expiresAt is null', () {
      final session = AuthSession(
        accessToken: 'token',
        providerName: 'email',
        createdAt: DateTime(2026, 1, 1),
      );
      expect(session.isExpired, false);
    });

    test('timeUntilExpiry returns duration', () {
      final session = AuthSession(
        accessToken: 'token',
        providerName: 'email',
        createdAt: DateTime(2026, 1, 1),
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      );
      expect(session.timeUntilExpiry, isNotNull);
      expect(session.timeUntilExpiry!.inMinutes, greaterThan(50));
    });

    test('copyWith updates fields', () {
      final session = AuthSession(
        accessToken: 'old-token',
        providerName: 'email',
        createdAt: DateTime(2026, 1, 1),
      );
      final refreshed = session.copyWith(
        accessToken: 'new-token',
        lastRefreshedAt: DateTime.now(),
      );
      expect(refreshed.accessToken, 'new-token');
      expect(refreshed.providerName, 'email');
      expect(refreshed.lastRefreshedAt, isNotNull);
    });
  });

  group('AuthCredentials', () {
    test('EmailCredentials stores email and password', () {
      const creds =
          EmailCredentials(email: 'test@example.com', password: 'secret');
      expect(creds.email, 'test@example.com');
      expect(creds.password, 'secret');
    });

    test('OAuthCredentials stores provider and tokens', () {
      const creds = OAuthCredentials(
        provider: 'google',
        idToken: 'id-token-123',
        accessToken: 'access-token-456',
      );
      expect(creds.provider, 'google');
      expect(creds.idToken, 'id-token-123');
      expect(creds.accessToken, 'access-token-456');
    });

    test('ApiKeyCredentials stores key', () {
      const creds = ApiKeyCredentials(apiKey: 'key-123');
      expect(creds.apiKey, 'key-123');
    });
  });

  group('AuthConfig', () {
    test('storage keys use prefix', () {
      const config = AuthConfig(
        providers: {},
        storagePrefix: 'myapp',
      );
      expect(config.accessTokenKey, 'myapp_access_token');
      expect(config.refreshTokenKey, 'myapp_refresh_token');
      expect(config.sessionKey, 'myapp_session');
      expect(config.userKey, 'myapp_user');
    });

    test('default storage prefix', () {
      const config = AuthConfig(providers: {});
      expect(config.accessTokenKey, 'juice_auth_access_token');
    });
  });

  group('AuthError', () {
    test('ProviderAuthError message includes provider', () {
      final error =
          ProviderAuthError('Wrong password', providerName: 'email');
      expect(error.message, 'Wrong password');
      expect(error.providerName, 'email');
    });

    test('UnknownProviderError includes provider name', () {
      final error = UnknownProviderError('github');
      expect(error.message, contains('github'));
    });

    test('RateLimitedError includes cooldown', () {
      final error = RateLimitedError(const Duration(seconds: 30));
      expect(error.message, contains('30'));
    });

    test('sealed AuthError hierarchy', () {
      AuthError error = NoRefreshTokenError();
      expect(error, isA<AuthError>());
      expect(error, isA<Exception>());

      error = RefreshFailedError('timeout');
      expect(error.message, contains('timeout'));

      error = StorageAuthError('write', 'disk full');
      expect(error.message, contains('write'));

      error = RestoreFailedError('no token');
      expect(error.message, contains('no token'));
    });

    test('toString includes runtimeType', () {
      final error = NoRefreshTokenError();
      expect(error.toString(), contains('NoRefreshTokenError'));
      expect(error.toString(), contains('No refresh token'));
    });
  });

  group('AuthProviderException', () {
    test('toString includes message and code', () {
      const e = AuthProviderException(
        'Invalid credentials',
        code: 'INVALID_PASSWORD',
      );
      expect(e.toString(), contains('Invalid credentials'));
      expect(e.toString(), contains('INVALID_PASSWORD'));
    });
  });

  // ======== Bloc-level integration tests ========

  group('AuthBloc', () {
    late MockStorageBloc storageBloc;
    late MockAuthProvider emailProvider;
    late AuthBloc bloc;
    late AuthConfig config;

    setUpAll(() {
      registerFallbackValue(FakeAuthCredentials());
      registerFallbackValue(FakeAuthSession());
    });

    setUp(() {
      storageBloc = MockStorageBloc();
      emailProvider = MockAuthProvider();

      when(() => emailProvider.name).thenReturn('email');
      when(() => emailProvider.supportsRefresh).thenReturn(true);
      when(() => emailProvider.dispose()).thenAnswer((_) async {});

      // Default storage stubs (no stored session)
      when(() => storageBloc.secureRead(any()))
          .thenAnswer((_) async => null);
      when(() => storageBloc.secureWrite(any(), any()))
          .thenAnswer((_) async {});
      when(() => storageBloc.secureDelete(any()))
          .thenAnswer((_) async {});

      config = AuthConfig(
        providers: {'email': emailProvider},
      );
    });

    tearDown(() async {
      await bloc.close();
    });

    group('initialization', () {
      test('starts in unknown state before initialization', () {
        bloc = AuthBloc(storageBloc: storageBloc);
        expect(bloc.state.status, AuthStatus.unknown);
      });

      test('transitions to unauthenticated when no session to restore',
          () async {
        bloc = AuthBloc(storageBloc: storageBloc);
        bloc.send(InitializeAuthEvent(config: config));

        await Future.delayed(_delay);

        expect(bloc.state.status, AuthStatus.unauthenticated);
      });

      test(
          'transitions to unauthenticated when restoreSessionOnInit is false',
          () async {
        final noRestoreConfig = AuthConfig(
          providers: {'email': emailProvider},
          restoreSessionOnInit: false,
        );

        bloc = AuthBloc(storageBloc: storageBloc);
        bloc.send(InitializeAuthEvent(config: noRestoreConfig));

        await Future.delayed(_delay);

        expect(bloc.state.status, AuthStatus.unauthenticated);
      });

      test('withConfig factory sends init event automatically', () async {
        bloc = AuthBloc.withConfig(config, storageBloc: storageBloc);

        await Future.delayed(_delay);

        expect(bloc.state.status, AuthStatus.unauthenticated);
      });

      test('restores session from storage when tokens exist', () async {
        // Stub stored session
        when(() => storageBloc.secureRead('juice_auth_session'))
            .thenAnswer((_) async => jsonEncode({
                  'providerName': 'email',
                  'expiresAt': DateTime.now()
                      .add(const Duration(hours: 1))
                      .toIso8601String(),
                }));
        when(() => storageBloc.secureRead('juice_auth_refresh_token'))
            .thenAnswer((_) async => 'stored-refresh-token');

        // Stub provider refresh
        when(() => emailProvider.refreshToken('stored-refresh-token'))
            .thenAnswer((_) async => _makeResult(
                  accessToken: 'new-access-token',
                  refreshToken: 'new-refresh-token',
                  expiresAt:
                      DateTime.now().add(const Duration(hours: 1)),
                ));

        bloc = AuthBloc.withConfig(config, storageBloc: storageBloc);
        await Future.delayed(_delay);

        expect(bloc.state.status, AuthStatus.authenticated);
        expect(bloc.state.user?.id, 'user-1');
        expect(bloc.state.session?.accessToken, 'new-access-token');
      });

      test('clears tokens and goes unauthenticated when restore fails',
          () async {
        when(() => storageBloc.secureRead('juice_auth_session'))
            .thenAnswer((_) async => jsonEncode({
                  'providerName': 'email',
                }));
        when(() => storageBloc.secureRead('juice_auth_refresh_token'))
            .thenAnswer((_) async => 'stale-token');

        when(() => emailProvider.refreshToken('stale-token'))
            .thenThrow(const AuthProviderException('Session expired'));

        bloc = AuthBloc.withConfig(config, storageBloc: storageBloc);
        await Future.delayed(_delay);

        expect(bloc.state.status, AuthStatus.unauthenticated);
        verify(() => storageBloc.secureDelete(any())).called(greaterThan(0));
      });
    });

    group('login', () {
      setUp(() async {
        bloc = AuthBloc.withConfig(
          AuthConfig(
            providers: {'email': emailProvider},
            restoreSessionOnInit: false,
          ),
          storageBloc: storageBloc,
        );
        await Future.delayed(_delay);
      });

      test('successful login transitions to authenticated', () async {
        when(() => emailProvider.authenticate(any()))
            .thenAnswer((_) async => _makeResult());

        bloc.loginWithEmail('test@example.com', 'password');
        await Future.delayed(_delay);

        expect(bloc.state.status, AuthStatus.authenticated);
        expect(bloc.state.user?.id, 'user-1');
        expect(bloc.state.session?.providerName, 'email');
        verify(() => storageBloc.secureWrite(any(), any()))
            .called(greaterThan(0));
      });

      test('login failure increments attempts and sets error', () async {
        when(() => emailProvider.authenticate(any()))
            .thenThrow(const AuthProviderException('Bad password'));

        bloc.loginWithEmail('test@example.com', 'wrong');
        await Future.delayed(_delay);

        expect(bloc.state.status, isNot(AuthStatus.authenticated));
        expect(bloc.state.loginAttempts, 1);
        expect(bloc.state.lastError, isA<ProviderAuthError>());
      });

      test('unknown provider sets error', () async {
        bloc.send(LoginEvent(
          providerName: 'github',
          credentials: const EmailCredentials(
            email: 'test@example.com',
            password: 'pass',
          ),
        ));
        await Future.delayed(_delay);

        expect(bloc.state.lastError, isA<UnknownProviderError>());
      });

      test('rate limiting after max attempts', () async {
        when(() => emailProvider.authenticate(any()))
            .thenThrow(const AuthProviderException('Bad password'));

        // Exhaust login attempts (default max: 5)
        for (var i = 0; i < 5; i++) {
          bloc.loginWithEmail('test@example.com', 'wrong');
          await Future.delayed(_delay);
        }

        // Next attempt should be rate-limited
        bloc.loginWithEmail('test@example.com', 'wrong');
        await Future.delayed(_delay);

        expect(bloc.state.lastError, isA<RateLimitedError>());
      });
    });

    group('logout', () {
      setUp(() async {
        bloc = AuthBloc.withConfig(
          AuthConfig(
            providers: {'email': emailProvider},
            restoreSessionOnInit: false,
          ),
          storageBloc: storageBloc,
        );
        await Future.delayed(_delay);

        // Login first
        when(() => emailProvider.authenticate(any()))
            .thenAnswer((_) async => _makeResult());
        bloc.loginWithEmail('test@example.com', 'password');
        await Future.delayed(_delay);
        expect(bloc.state.isAuthenticated, true);
      });

      test('logout transitions to unauthenticated', () async {
        when(() => emailProvider.revokeSession(any()))
            .thenAnswer((_) async {});

        bloc.logout();
        await Future.delayed(_delay);

        expect(bloc.state.status, AuthStatus.unauthenticated);
        expect(bloc.state.user, isNull);
        expect(bloc.state.session, isNull);
      });

      test('logout clears stored tokens', () async {
        when(() => emailProvider.revokeSession(any()))
            .thenAnswer((_) async {});

        bloc.logout();
        await Future.delayed(_delay);

        verify(() => storageBloc.secureDelete(any()))
            .called(greaterThan(0));
      });

      test('force logout skips provider revocation', () async {
        bloc.logout(force: true);
        await Future.delayed(_delay);

        expect(bloc.state.status, AuthStatus.unauthenticated);
        verifyNever(() => emailProvider.revokeSession(any()));
      });

      test('logout succeeds even when revocation fails', () async {
        when(() => emailProvider.revokeSession(any()))
            .thenThrow(Exception('Network error'));

        bloc.logout();
        await Future.delayed(_delay);

        expect(bloc.state.status, AuthStatus.unauthenticated);
      });
    });

    group('token refresh', () {
      setUp(() async {
        bloc = AuthBloc.withConfig(
          AuthConfig(
            providers: {'email': emailProvider},
            restoreSessionOnInit: false,
          ),
          storageBloc: storageBloc,
        );
        await Future.delayed(_delay);

        // Login with a refresh token
        when(() => emailProvider.authenticate(any()))
            .thenAnswer((_) async => _makeResult(
                  refreshToken: 'refresh-token',
                  expiresAt:
                      DateTime.now().add(const Duration(hours: 1)),
                ));
        bloc.loginWithEmail('test@example.com', 'password');
        await Future.delayed(_delay);
      });

      test('successful refresh updates session tokens', () async {
        when(() => emailProvider.refreshToken('refresh-token'))
            .thenAnswer((_) async => _makeResult(
                  accessToken: 'new-access',
                  refreshToken: 'new-refresh',
                  expiresAt:
                      DateTime.now().add(const Duration(hours: 2)),
                ));

        bloc.refreshToken();
        await Future.delayed(_delay);

        expect(bloc.state.session?.accessToken, 'new-access');
        expect(bloc.state.isRefreshing, false);
      });

      test('refresh failure marks session as expired', () async {
        when(() => emailProvider.refreshToken('refresh-token'))
            .thenThrow(const AuthProviderException('Token revoked'));

        bloc.refreshToken();
        await Future.delayed(_delay);

        expect(bloc.state.status, AuthStatus.sessionExpired);
        expect(bloc.state.isRefreshing, false);
        expect(bloc.state.lastError, isA<RefreshFailedError>());
      });

      test('refresh without refresh token sets error', () async {
        // Login without refresh token
        when(() => emailProvider.authenticate(any()))
            .thenAnswer((_) async => _makeResult(refreshToken: null));
        bloc.loginWithEmail('test@example.com', 'password');
        await Future.delayed(_delay);

        bloc.refreshToken();
        await Future.delayed(_delay);

        expect(bloc.state.lastError, isA<NoRefreshTokenError>());
      });
    });

    group('update user', () {
      setUp(() async {
        bloc = AuthBloc.withConfig(
          AuthConfig(
            providers: {'email': emailProvider},
            restoreSessionOnInit: false,
          ),
          storageBloc: storageBloc,
        );
        await Future.delayed(_delay);

        // Login first
        when(() => emailProvider.authenticate(any()))
            .thenAnswer((_) async => _makeResult());
        bloc.loginWithEmail('test@example.com', 'password');
        await Future.delayed(_delay);
      });

      test('updates user profile in state', () async {
        bloc.updateUser(const AuthUser(
          id: 'user-1',
          displayName: 'Updated Name',
          email: 'new@example.com',
        ));
        await Future.delayed(_delay);

        expect(bloc.state.user?.displayName, 'Updated Name');
        expect(bloc.state.user?.email, 'new@example.com');
      });

      test('ignores update when not authenticated', () async {
        // Logout first
        when(() => emailProvider.revokeSession(any()))
            .thenAnswer((_) async {});
        bloc.logout();
        await Future.delayed(_delay);

        bloc.updateUser(const AuthUser(id: 'user-1'));
        await Future.delayed(_delay);

        expect(bloc.state.user, isNull);
      });
    });

    group('convenience methods', () {
      setUp(() async {
        bloc = AuthBloc.withConfig(
          AuthConfig(
            providers: {'email': emailProvider},
            restoreSessionOnInit: false,
          ),
          storageBloc: storageBloc,
        );
        await Future.delayed(_delay);
      });

      test('loginWithEmail sends correct event', () async {
        when(() => emailProvider.authenticate(any()))
            .thenAnswer((_) async => _makeResult());

        bloc.loginWithEmail('user@test.com', 'pass');
        await Future.delayed(_delay);

        verify(() => emailProvider.authenticate(any())).called(1);
        expect(bloc.state.isAuthenticated, true);
      });

      test('loginWithOAuth sends correct event', () async {
        final oauthProvider = MockAuthProvider();
        when(() => oauthProvider.name).thenReturn('google');
        when(() => oauthProvider.supportsRefresh).thenReturn(true);
        when(() => oauthProvider.dispose()).thenAnswer((_) async {});
        when(() => oauthProvider.authenticate(any()))
            .thenAnswer((_) async => _makeResult());

        final oauthBloc = AuthBloc.withConfig(
          AuthConfig(
            providers: {'google': oauthProvider},
            restoreSessionOnInit: false,
          ),
          storageBloc: storageBloc,
        );
        await Future.delayed(_delay);

        oauthBloc.loginWithOAuth('google', 'id-token-123',
            accessToken: 'oauth-access');
        await Future.delayed(_delay);

        verify(() => oauthProvider.authenticate(any())).called(1);
        expect(oauthBloc.state.isAuthenticated, true);

        await oauthBloc.close();
      });
    });
  });
}
