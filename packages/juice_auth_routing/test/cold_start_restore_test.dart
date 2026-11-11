import 'dart:async';

import 'package:flutter/widgets.dart' show SizedBox;
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_auth/juice_auth.dart';
import 'package:juice_auth_routing/juice_auth_routing.dart';
import 'package:juice_routing/juice_routing.dart';
import 'package:juice_storage/juice_storage.dart';
import 'package:mocktail/mocktail.dart';

class MockStorageBloc extends Mock implements StorageBloc {}

class MockAuthProvider extends Mock implements AuthProvider {}

class FakeSession extends Fake implements AuthSession {}

/// ISSUES #29: a signed-in user's cold start, with the home route behind
/// [AuthBlocAuthGuard].
///
/// `AuthState` starts as `AuthStatus.unknown` and stays there until the
/// stored session has been restored (a provider round trip). juice_routing
/// runs the guards on the INITIAL path, so a guard that read "not yet known"
/// as "signed out" started a signed-in user on the login page — and left
/// them there, since a guard is asked on navigation only. Reproduced on
/// 2026-11-10 with the blocs below, before the fix.
///
/// The ruling (Kevin, 2026-11-10: "wait for the answer"): the AuthBloc-wired
/// guards wait until the session is known, then decide; a restore that does
/// not answer in time refuses the navigation, loudly. No guard falls back
/// to "signed out".
void main() {
  late MockStorageBloc storage;
  late MockAuthProvider provider;
  late Completer<AuthResult> restoring;
  final closers = <Future<void> Function()>[];

  const config = AuthConfig(providers: {});

  setUpAll(() => registerFallbackValue(FakeSession()));

  setUp(() {
    storage = MockStorageBloc();
    provider = MockAuthProvider();
    restoring = Completer<AuthResult>();
    when(() => provider.name).thenReturn('email');
    when(() => provider.supportsRefresh).thenReturn(true);
    when(() => provider.dispose()).thenAnswer((_) async {});
    when(() => provider.revokeSession(any())).thenAnswer((_) async {});
    // The restore's round trip to the provider: held until the test says.
    when(() => provider.refreshToken(any()))
        .thenAnswer((_) => restoring.future);
    when(() => storage.secureRead(any())).thenAnswer((_) async => null);
    when(() => storage.secureWrite(any(), any())).thenAnswer((_) async {});
    when(() => storage.secureDelete(any())).thenAnswer((_) async {});
  });

  tearDown(() async {
    for (final close in closers.reversed) {
      await close();
    }
    closers.clear();
  });

  /// A session from an earlier launch is in secure storage.
  void signedInLastTime() {
    when(() => storage.secureRead(config.sessionKey))
        .thenAnswer((_) async => '{"providerName":"email"}');
    when(() => storage.secureRead(config.refreshTokenKey))
        .thenAnswer((_) async => 'refresh-0');
  }

  void restoreSucceeds() => restoring.complete(AuthResult(
        accessToken: 'tok',
        refreshToken: 'refresh-1',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
        user: const AuthUser(id: 'u1', email: 'a@b.c'),
      ));

  AuthBloc auth() {
    final bloc = AuthBloc.withConfig(
      AuthConfig(providers: {'email': provider}),
      storageBloc: storage,
    );
    closers.add(bloc.close);
    return bloc;
  }

  /// Home is guarded; login is open.
  RoutingBloc routing(AuthBloc authBloc) {
    final bloc = RoutingBloc.withConfig(
      RoutingConfig(
        routes: [
          RouteConfig(
            path: '/',
            builder: (_) => const SizedBox.shrink(),
            guards: [AuthBlocAuthGuard(authBloc)],
          ),
          RouteConfig(path: '/login', builder: (_) => const SizedBox.shrink()),
        ],
        initialPath: '/',
      ),
    );
    closers.add(bloc.close);
    return bloc;
  }

  /// Every location the app showed, in order.
  List<String> pagesShown(RoutingBloc bloc) {
    final shown = <String>[];
    final sub = bloc.stream.listen((s) {
      final path = s.state.currentPath;
      if (path != null && (shown.isEmpty || shown.last != path)) {
        shown.add(path);
      }
    });
    closers.add(sub.cancel);
    return shown;
  }

  Future<void> settle([int ms = 60]) =>
      Future<void>.delayed(Duration(milliseconds: ms));

  /// Routes for the guest and role cases.
  RoutingBloc routingWith(AuthBloc authBloc,
      {required String initialPath, Duration? restoreTimeout}) {
    final t = restoreTimeout ?? AuthBlocAuthGuard.defaultRestoreTimeout;
    final bloc = RoutingBloc.withConfig(
      RoutingConfig(
        routes: [
          RouteConfig(
            path: '/',
            builder: (_) => const SizedBox.shrink(),
            guards: [AuthBlocAuthGuard(authBloc, restoreTimeout: t)],
          ),
          RouteConfig(
            path: '/login',
            builder: (_) => const SizedBox.shrink(),
            guards: [AuthBlocGuestGuard(authBloc, restoreTimeout: t)],
          ),
          RouteConfig(
            path: '/admin',
            builder: (_) => const SizedBox.shrink(),
            guards: [AuthBlocRoleGuard(authBloc, 'admin', restoreTimeout: t)],
          ),
        ],
        initialPath: initialPath,
      ),
    );
    closers.add(bloc.close);
    return bloc;
  }

  group('routing built while the session is still being restored', () {
    test(
        'a signed-in user: the navigation waits, then lands on home — the '
        'login page is never shown', () async {
      signedInLastTime();
      final authBloc = auth();
      final routingBloc = routing(authBloc);
      final shown = pagesShown(routingBloc);
      await settle();

      expect(authBloc.state.status, AuthStatus.unknown,
          reason: 'the restore is still waiting on the provider');
      expect(routingBloc.state.currentPath, isNull,
          reason: 'no page yet: the guard has not answered');
      expect(routingBloc.state.pending?.targetPath, '/',
          reason: 'the pending navigation is what a splash is drawn from');
      expect(routingBloc.state.pending?.currentGuardName, 'AuthGuard');
      expect(shown, isEmpty);

      restoreSucceeds();
      await settle();

      expect(authBloc.state.status, AuthStatus.authenticated);
      expect(routingBloc.state.currentPath, '/');
      expect(routingBloc.state.pending, isNull);
      expect(routingBloc.state.error, isNull);
      expect(shown, ['/']);
    });

    test(
        'the restore fails: the answer is "signed out", and the user is '
        'sent to login with the way back', () async {
      signedInLastTime();
      final authBloc = auth();
      final routingBloc = routing(authBloc);
      final shown = pagesShown(routingBloc);
      await settle();
      expect(shown, isEmpty);

      restoring.completeError(StateError('refresh token revoked'));
      await settle();

      expect(authBloc.state.status, isNot(AuthStatus.unknown));
      expect(authBloc.state.isAuthenticated, isFalse);
      expect(routingBloc.state.currentPath, '/login');
      expect(routingBloc.state.current!.query['returnTo'], '/');
      expect(shown, ['/login']);
    });

    test(
        'the restore never answers: after restoreTimeout the navigation is '
        'REFUSED with the timeout — no page, and no guess of "signed out"',
        () async {
      signedInLastTime();
      final authBloc = auth();
      final routingBloc = routingWith(authBloc,
          initialPath: '/', restoreTimeout: const Duration(milliseconds: 80));
      final shown = pagesShown(routingBloc);
      await settle(30);
      expect(routingBloc.state.error, isNull, reason: 'still waiting');

      await settle(150);

      expect(authBloc.state.status, AuthStatus.unknown);
      final error = routingBloc.state.error;
      expect(error, isA<GuardExceptionError>());
      error as GuardExceptionError;
      expect(error.exception, isA<TimeoutException>());
      expect(error.guardName, 'AuthGuard');
      expect(error.path, '/');
      expect(routingBloc.state.currentPath, isNull);
      expect(shown, isEmpty,
          reason: 'not the login page: a guard that cannot tell does not '
              'guess');
    });

    test('the default wait is ten seconds, on all three guards', () {
      final authBloc = auth();
      expect(
          AuthBlocAuthGuard.defaultRestoreTimeout, const Duration(seconds: 10));
      expect(AuthBlocAuthGuard(authBloc).restoreTimeout,
          const Duration(seconds: 10));
      expect(AuthBlocGuestGuard(authBloc).restoreTimeout,
          const Duration(seconds: 10));
      expect(AuthBlocRoleGuard(authBloc, 'admin').restoreTimeout,
          const Duration(seconds: 10));
    });

    test(
        'with AuthBlocRoutingBridge too: still home, once — the bridge has '
        'no login page to undo', () async {
      signedInLastTime();
      final authBloc = auth();
      final routingBloc = routing(authBloc);
      final shown = pagesShown(routingBloc);
      final bridge = AuthBlocRoutingBridge(
        authBloc,
        routingBloc,
        onAuthenticated: (_) => routingBloc.navigate(
            routingBloc.state.current?.query['returnTo'] ?? '/',
            replace: true),
      )..start();
      closers.add(() async => bridge.dispose());
      await settle();

      restoreSucceeds();
      await settle();

      expect(routingBloc.state.currentPath, '/');
      expect(shown, ['/']);
    });

    test(
        'a signed-in user whose cold start is the login page (a deep link): '
        'the guest guard waits too, then sends them home', () async {
      signedInLastTime();
      final authBloc = auth();
      final routingBloc = routingWith(authBloc, initialPath: '/login');
      final shown = pagesShown(routingBloc);
      await settle();
      expect(shown, isEmpty,
          reason: 'not yet known is not "a guest": the login page is not '
              'shown to a user about to be signed in');

      restoreSucceeds();
      await settle();

      expect(routingBloc.state.currentPath, '/');
      expect(shown, ['/']);
    });

    test(
        'a role-guarded cold start: the guard waits for the user before it '
        'asks for the role', () async {
      signedInLastTime();
      final authBloc = auth();
      final routingBloc = routingWith(authBloc, initialPath: '/admin');
      final shown = pagesShown(routingBloc);
      await settle();
      expect(routingBloc.state.error, isNull,
          reason: 'no user yet is not "lacks the role"');
      expect(shown, isEmpty);

      restoring.complete(AuthResult(
        accessToken: 'tok',
        refreshToken: 'refresh-1',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
        user: const AuthUser(id: 'u1', email: 'a@b.c', roles: {'admin'}),
      ));
      await settle();

      expect(routingBloc.state.currentPath, '/admin');
      expect(shown, ['/admin']);
    });

    test('the AuthBloc closes while a guard waits: refused, loudly', () async {
      signedInLastTime();
      final authBloc = auth();
      final routingBloc = routing(authBloc);
      await settle();
      expect(routingBloc.state.pending, isNotNull);

      await authBloc.close();
      await settle();

      final error = routingBloc.state.error;
      expect(error, isA<GuardExceptionError>());
      expect((error as GuardExceptionError).exception, isA<StateError>());
      expect(routingBloc.state.currentPath, isNull);
    });
  });

  group('for comparison', () {
    test(
        'the session is already known when routing is built: home at once, '
        'nothing waits', () async {
      signedInLastTime();
      final authBloc = auth();
      await settle();
      restoreSucceeds();
      await authBloc.waitFor((s) => s.status != AuthStatus.unknown,
          timeout: const Duration(seconds: 2));

      final routingBloc = routing(authBloc);
      final shown = pagesShown(routingBloc);
      await settle();

      expect(routingBloc.state.currentPath, '/');
      expect(shown, ['/']);
    });

    test('a user who was never signed in starts on the login page', () async {
      final authBloc = auth();
      final routingBloc = routing(authBloc);
      final shown = pagesShown(routingBloc);
      await settle();

      expect(authBloc.state.status, AuthStatus.unauthenticated);
      expect(routingBloc.state.currentPath, '/login');
      expect(shown, ['/login']);
    });
  });
}
