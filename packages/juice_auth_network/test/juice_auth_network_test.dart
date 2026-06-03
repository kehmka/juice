import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:juice/juice.dart';
import 'package:juice_auth/juice_auth.dart';
import 'package:juice_auth_network/juice_auth_network.dart';
import 'package:juice_network/juice_network.dart';
import 'package:juice_storage/juice_storage.dart';
import 'package:mocktail/mocktail.dart';

class MockStorageBloc extends Mock implements StorageBloc {}

class MockAuthProvider extends Mock implements AuthProvider {}

class FakeAuthCredentials extends Fake implements AuthCredentials {}

const _delay = Duration(milliseconds: 50);

AuthResult _result({
  String accessToken = 'access-token',
  String? refreshToken = 'refresh-token',
  DateTime? expiresAt,
  String userId = 'user-1',
}) =>
    AuthResult(
      accessToken: accessToken,
      refreshToken: refreshToken,
      expiresAt: expiresAt,
      user: AuthUser(id: userId, email: 'test@example.com'),
    );

void main() {
  late MockStorageBloc storageBloc;
  late MockAuthProvider provider;
  late AuthBloc authBloc;

  setUpAll(() {
    registerFallbackValue(FakeAuthCredentials());
  });

  setUp(() {
    storageBloc = MockStorageBloc();
    provider = MockAuthProvider();

    when(() => provider.name).thenReturn('email');
    when(() => provider.supportsRefresh).thenReturn(true);
    when(() => provider.dispose()).thenAnswer((_) async {});

    when(() => storageBloc.secureRead(any())).thenAnswer((_) async => null);
    when(() => storageBloc.secureWrite(any(), any())).thenAnswer((_) async {});
    when(() => storageBloc.secureDelete(any())).thenAnswer((_) async {});

    authBloc = AuthBloc.withConfig(
      AuthConfig(
        providers: {'email': provider},
        restoreSessionOnInit: false,
      ),
      storageBloc: storageBloc,
    );
  });

  tearDown(() async {
    await authBloc.close();
  });

  /// Log in so the bloc has an authenticated session with the given token.
  Future<void> login({
    String accessToken = 'access-token',
    String? refreshToken = 'refresh-token',
  }) async {
    when(() => provider.authenticate(any())).thenAnswer((_) async => _result(
          accessToken: accessToken,
          refreshToken: refreshToken,
          expiresAt: DateTime.now().add(const Duration(hours: 1)),
        ));
    authBloc.loginWithEmail('test@example.com', 'password');
    await Future.delayed(_delay);
  }

  group('AuthBlocIdentityProvider', () {
    test('returns user id when authenticated', () async {
      await login();
      final identity = AuthBlocIdentityProvider(authBloc);
      expect(identity.call(), 'user-1');
    });

    test('returns null when unauthenticated', () async {
      await Future.delayed(_delay); // settle init → unauthenticated
      final identity = AuthBlocIdentityProvider(authBloc);
      expect(identity.call(), isNull);
    });
  });

  group('AuthBlocAuthInterceptor', () {
    test('injects the current access token as a Bearer header', () async {
      await login(accessToken: 'tok-123');
      final interceptor = AuthBlocAuthInterceptor(authBloc);

      final result = await interceptor.onRequest(RequestOptions(path: '/x'));

      expect(result.headers['Authorization'], 'Bearer tok-123');
    });

    test('adds no header when there is no session', () async {
      await Future.delayed(_delay); // unauthenticated
      final interceptor = AuthBlocAuthInterceptor(authBloc);

      final result = await interceptor.onRequest(RequestOptions(path: '/x'));

      expect(result.headers.containsKey('Authorization'), isFalse);
    });

    test('reflects a newer token on a later request (no stale token)',
        () async {
      await login(accessToken: 'first');
      final interceptor = AuthBlocAuthInterceptor(authBloc);

      final r1 = await interceptor.onRequest(RequestOptions(path: '/x'));
      expect(r1.headers['Authorization'], 'Bearer first');

      // Update the session as a refresh would.
      await login(accessToken: 'second');
      final r2 = await interceptor.onRequest(RequestOptions(path: '/x'));
      expect(r2.headers['Authorization'], 'Bearer second');
    });
  });

  group('end-to-end through FetchBloc', () {
    test('FetchBloc request carries the AuthBloc token', () async {
      await login(accessToken: 'e2e-token');

      final dio = Dio();
      final dioAdapter = DioAdapter(dio: dio);
      dioAdapter.onGet(
        '/me',
        (server) => server.reply(200, {'ok': true}, headers: {
          'content-type': ['application/json'],
        }),
      );

      final fetchStorage = MockStorageBloc();
      when(() => fetchStorage.hiveOpenBox(any())).thenAnswer((_) async {});
      when(() => fetchStorage.hiveRead<dynamic>(any(), any()))
          .thenAnswer((_) async => null);

      final fetchBloc = FetchBloc(storageBloc: fetchStorage, dio: dio);

      // Capture the outgoing Authorization header after the auth interceptor
      // has run. Registered after init so it sits later in the request chain.
      String? sentAuthHeader;

      Future<void> settle(EventBase event) async {
        final completer = Completer<void>();
        late StreamSubscription<StreamStatus<FetchState>> sub;
        sub = fetchBloc.stream.listen((status) {
          if (status is! WaitingStatus) {
            if (!completer.isCompleted) completer.complete();
            sub.cancel();
          }
        });
        try {
          await fetchBloc.send(event);
        } catch (_) {}
        await completer.future.timeout(const Duration(seconds: 5));
      }

      await settle(InitializeFetchEvent(
        config: const FetchConfig(),
        interceptors: [AuthBlocAuthInterceptor(authBloc)],
      ));

      dio.interceptors.add(InterceptorsWrapper(
        onRequest: (options, handler) {
          sentAuthHeader = options.headers['Authorization'] as String?;
          handler.next(options);
        },
      ));

      await settle(GetEvent(url: '/me', cachePolicy: CachePolicy.networkOnly));

      expect(sentAuthHeader, 'Bearer e2e-token');
      expect(fetchBloc.state.stats.successCount, 1);

      await fetchBloc.close();
    });
  });

  group('AuthBlocRefreshStrategy', () {
    test('triggers refresh and resolves with the new access token', () async {
      await login(accessToken: 'old', refreshToken: 'refresh-token');

      when(() => provider.refreshToken('refresh-token'))
          .thenAnswer((_) async => _result(
                accessToken: 'refreshed',
                refreshToken: 'refresh-token',
                expiresAt: DateTime.now().add(const Duration(hours: 1)),
              ));

      final strategy = AuthBlocRefreshStrategy(authBloc);
      final token = await strategy.refresh();

      expect(token, 'refreshed');
      expect(authBloc.state.session?.accessToken, 'refreshed');
    });

    test('resolves null when refresh fails (session expired)', () async {
      await login(accessToken: 'old', refreshToken: 'refresh-token');

      when(() => provider.refreshToken('refresh-token'))
          .thenThrow(const AuthProviderException('revoked'));

      final strategy = AuthBlocRefreshStrategy(authBloc);
      final token = await strategy.refresh();

      expect(token, isNull);
      expect(authBloc.state.status, AuthStatus.sessionExpired);
    });
  });
}
