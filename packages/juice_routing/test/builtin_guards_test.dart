import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_routing/juice_routing.dart';

void main() {
  group('AuthGuard', () {
    late RoutingBloc bloc;

    tearDown(() async {
      await bloc.close();
    });

    test('allows authenticated users', () async {
      final config = RoutingConfig(
        routes: [
          RouteConfig(path: '/', builder: (_) => const SizedBox()),
          RouteConfig(path: '/login', builder: (_) => const SizedBox()),
          RouteConfig(
            path: '/dashboard',
            builder: (_) => const SizedBox(),
            guards: [AuthGuard(isAuthenticated: () => true)],
          ),
        ],
      );
      bloc = RoutingBloc.withConfig(config);
      await Future.delayed(const Duration(milliseconds: 50));

      bloc.navigate('/dashboard');
      await Future.delayed(const Duration(milliseconds: 100));

      expect(bloc.state.currentPath, '/dashboard');
      expect(bloc.state.error, isNull);
    });

    test('redirects unauthenticated users to login', () async {
      final config = RoutingConfig(
        routes: [
          RouteConfig(path: '/', builder: (_) => const SizedBox()),
          RouteConfig(path: '/login', builder: (_) => const SizedBox()),
          RouteConfig(
            path: '/dashboard',
            builder: (_) => const SizedBox(),
            guards: [AuthGuard(isAuthenticated: () => false)],
          ),
        ],
      );
      bloc = RoutingBloc.withConfig(config);
      await Future.delayed(const Duration(milliseconds: 50));

      bloc.navigate('/dashboard');
      await Future.delayed(const Duration(milliseconds: 100));

      expect(bloc.state.currentPath, '/login');
      expect(bloc.state.error, isNull);
    });

    test('uses custom login path', () async {
      final config = RoutingConfig(
        routes: [
          RouteConfig(path: '/', builder: (_) => const SizedBox()),
          RouteConfig(path: '/auth/signin', builder: (_) => const SizedBox()),
          RouteConfig(
            path: '/dashboard',
            builder: (_) => const SizedBox(),
            guards: [
              AuthGuard(
                isAuthenticated: () => false,
                loginPath: '/auth/signin',
              ),
            ],
          ),
        ],
      );
      bloc = RoutingBloc.withConfig(config);
      await Future.delayed(const Duration(milliseconds: 50));

      bloc.navigate('/dashboard');
      await Future.delayed(const Duration(milliseconds: 100));

      expect(bloc.state.currentPath, '/auth/signin');
    });

    test('includes returnTo in redirect', () async {
      final guard = AuthGuard(isAuthenticated: () => false);
      final context = RouteContext(
        targetPath: '/dashboard',
        params: {},
        query: {},
        currentState: RoutingState.initial,
        targetRoute: RouteConfig(
          path: '/dashboard',
          builder: (_) => const SizedBox(),
        ),
      );

      final result = await guard.check(context);
      expect(result, isA<RedirectResult>());
      final redirect = result as RedirectResult;
      expect(redirect.path, '/login');
      expect(redirect.returnTo, '/dashboard');
    });
  });

  group('RoleGuard', () {
    late RoutingBloc bloc;

    tearDown(() async {
      await bloc.close();
    });

    test('allows users with required role', () async {
      final config = RoutingConfig(
        routes: [
          RouteConfig(path: '/', builder: (_) => const SizedBox()),
          RouteConfig(
            path: '/admin',
            builder: (_) => const SizedBox(),
            guards: [RoleGuard(hasRole: () => true, roleName: 'admin')],
          ),
        ],
      );
      bloc = RoutingBloc.withConfig(config);
      await Future.delayed(const Duration(milliseconds: 50));

      bloc.navigate('/admin');
      await Future.delayed(const Duration(milliseconds: 50));

      expect(bloc.state.currentPath, '/admin');
      expect(bloc.state.error, isNull);
    });

    test('blocks users without required role', () async {
      final config = RoutingConfig(
        routes: [
          RouteConfig(path: '/', builder: (_) => const SizedBox()),
          RouteConfig(
            path: '/admin',
            builder: (_) => const SizedBox(),
            guards: [RoleGuard(hasRole: () => false, roleName: 'admin')],
          ),
        ],
      );
      bloc = RoutingBloc.withConfig(config);
      await Future.delayed(const Duration(milliseconds: 50));

      bloc.navigate('/admin');
      await Future.delayed(const Duration(milliseconds: 50));

      expect(bloc.state.currentPath, '/'); // Still at root
      expect(bloc.state.error, isA<GuardBlockedError>());
      final error = bloc.state.error as GuardBlockedError;
      expect(error.reason, 'Requires role: admin');
    });

    test('includes role name in guard name', () {
      final guard = RoleGuard(hasRole: () => true, roleName: 'editor');
      expect(guard.name, 'RoleGuard(editor)');
    });
  });

  group('GuestGuard', () {
    late RoutingBloc bloc;

    tearDown(() async {
      await bloc.close();
    });

    test('allows unauthenticated users', () async {
      final config = RoutingConfig(
        routes: [
          RouteConfig(path: '/', builder: (_) => const SizedBox()),
          RouteConfig(
            path: '/login',
            builder: (_) => const SizedBox(),
            guards: [GuestGuard(isAuthenticated: () => false)],
          ),
        ],
      );
      bloc = RoutingBloc.withConfig(config);
      await Future.delayed(const Duration(milliseconds: 50));

      bloc.navigate('/login');
      await Future.delayed(const Duration(milliseconds: 100));

      expect(bloc.state.currentPath, '/login');
      expect(bloc.state.error, isNull);
    });

    test('redirects authenticated users to home', () async {
      final config = RoutingConfig(
        routes: [
          RouteConfig(path: '/', builder: (_) => const SizedBox()),
          RouteConfig(
            path: '/login',
            builder: (_) => const SizedBox(),
            guards: [GuestGuard(isAuthenticated: () => true)],
          ),
        ],
      );
      bloc = RoutingBloc.withConfig(config);
      await Future.delayed(const Duration(milliseconds: 50));

      bloc.navigate('/login');
      await Future.delayed(const Duration(milliseconds: 100));

      // Should redirect to '/' (default)
      expect(bloc.state.currentPath, '/');
    });

    test('uses custom redirect path', () async {
      final config = RoutingConfig(
        routes: [
          RouteConfig(path: '/', builder: (_) => const SizedBox()),
          RouteConfig(path: '/dashboard', builder: (_) => const SizedBox()),
          RouteConfig(
            path: '/login',
            builder: (_) => const SizedBox(),
            guards: [
              GuestGuard(
                isAuthenticated: () => true,
                redirectPath: '/dashboard',
              ),
            ],
          ),
        ],
      );
      bloc = RoutingBloc.withConfig(config);
      await Future.delayed(const Duration(milliseconds: 50));

      bloc.navigate('/login');
      await Future.delayed(const Duration(milliseconds: 100));

      expect(bloc.state.currentPath, '/dashboard');
    });
  });
}
