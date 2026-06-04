import 'package:flutter/widgets.dart' show SizedBox;
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_auth/juice_auth.dart';
import 'package:juice_auth_routing/juice_auth_routing.dart';
import 'package:juice_routing/juice_routing.dart';
import 'package:juice_storage/juice_storage.dart';
import 'package:mocktail/mocktail.dart';

class MockStorageBloc extends Mock implements StorageBloc {}

class MockAuthProvider extends Mock implements AuthProvider {}

class FakeCreds extends Fake implements AuthCredentials {}

class FakeSession extends Fake implements AuthSession {}

void main() {
  late MockStorageBloc storage;
  late MockAuthProvider provider;
  late AuthBloc authBloc;
  late RoutingBloc routingBloc;

  setUpAll(() {
    registerFallbackValue(FakeCreds());
    registerFallbackValue(FakeSession());
  });

  setUp(() {
    storage = MockStorageBloc();
    provider = MockAuthProvider();
    when(() => provider.name).thenReturn('email');
    when(() => provider.supportsRefresh).thenReturn(true);
    when(() => provider.dispose()).thenAnswer((_) async {});
    when(() => provider.revokeSession(any())).thenAnswer((_) async {});
    when(() => storage.secureRead(any())).thenAnswer((_) async => null);
    when(() => storage.secureWrite(any(), any())).thenAnswer((_) async {});
    when(() => storage.secureDelete(any())).thenAnswer((_) async {});

    authBloc = AuthBloc.withConfig(
      AuthConfig(providers: {'email': provider}, restoreSessionOnInit: false),
      storageBloc: storage,
    );

    routingBloc = RoutingBloc.withConfig(
      RoutingConfig(
        routes: [
          RouteConfig(path: '/', builder: (_) => const SizedBox.shrink()),
          RouteConfig(
            path: '/login',
            builder: (_) => const SizedBox.shrink(),
            guards: [AuthBlocGuestGuard(authBloc)],
          ),
          RouteConfig(
            path: '/profile',
            builder: (_) => const SizedBox.shrink(),
            guards: [AuthBlocAuthGuard(authBloc)],
          ),
          RouteConfig(
            path: '/admin',
            builder: (_) => const SizedBox.shrink(),
            guards: [AuthBlocRoleGuard(authBloc, 'admin')],
          ),
        ],
        initialPath: '/',
      ),
    );
  });

  tearDown(() async {
    await routingBloc.close();
    await authBloc.close();
  });

  Future<void> settle([int ms = 60]) =>
      Future<void>.delayed(Duration(milliseconds: ms));

  Future<void> login({Set<String> roles = const {}}) async {
    when(() => provider.authenticate(any())).thenAnswer((_) async => AuthResult(
          accessToken: 'tok',
          refreshToken: 'r',
          expiresAt: DateTime.now().add(const Duration(hours: 1)),
          user: AuthUser(id: 'u1', email: 'a@b.c', roles: roles),
        ));
    authBloc.loginWithEmail('a@b.c', 'pw');
    await settle();
  }

  group('AuthBlocAuthGuard', () {
    test('redirects unauthenticated users to /login', () async {
      await settle();
      routingBloc.navigate('/profile');
      await settle();
      expect(routingBloc.state.currentPath, '/login');
    });

    test('allows authenticated users through', () async {
      await login();
      routingBloc.navigate('/profile');
      await settle();
      expect(routingBloc.state.currentPath, '/profile');
    });
  });

  group('AuthBlocGuestGuard', () {
    test('redirects authenticated users away from /login', () async {
      await login();
      routingBloc.navigate('/login');
      await settle();
      expect(routingBloc.state.currentPath, '/'); // redirectPath default
    });
  });

  group('AuthBlocRoleGuard', () {
    test('blocks without the role', () async {
      await login(); // no roles
      routingBloc.navigate('/admin');
      await settle();
      expect(routingBloc.state.currentPath, isNot('/admin'));
    });

    test('allows with the role', () async {
      await login(roles: {'admin'});
      routingBloc.navigate('/admin');
      await settle();
      expect(routingBloc.state.currentPath, '/admin');
    });
  });

  group('AuthBlocRoutingBridge', () {
    test('redirects to /login when auth is lost mid-session', () async {
      await login();
      routingBloc.navigate('/profile');
      await settle();
      expect(routingBloc.state.currentPath, '/profile');

      final bridge = AuthBlocRoutingBridge(authBloc, routingBloc)..start();
      authBloc.logout(force: true);
      await settle();

      expect(routingBloc.state.currentPath, '/login');
      bridge.dispose();
    });

    test('calls onAuthenticated when the user logs in', () async {
      await settle();
      AuthState? seen;
      final bridge = AuthBlocRoutingBridge(
        authBloc,
        routingBloc,
        onAuthenticated: (s) => seen = s,
      )..start();

      await login();

      expect(seen?.isAuthenticated, isTrue);
      bridge.dispose();
    });
  });
}
