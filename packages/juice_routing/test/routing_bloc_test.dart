import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_routing/juice_routing.dart';

void main() {
  group('RoutingBloc', () {
    late RoutingBloc bloc;
    late RoutingConfig config;

    setUp(() {
      config = RoutingConfig(
        routes: [
          RouteConfig(path: '/', builder: (_) => const SizedBox()),
          RouteConfig(path: '/profile/:userId', builder: (_) => const SizedBox()),
          RouteConfig(path: '/settings', builder: (_) => const SizedBox()),
        ],
        initialPath: '/',
      );
    });

    tearDown(() async {
      await bloc.close();
    });

    group('initialization', () {
      test('initializes with initial path', () async {
        bloc = RoutingBloc();
        bloc.send(InitializeRoutingEvent(config: config));

        // Wait for event processing
        await Future.delayed(const Duration(milliseconds: 50));

        expect(bloc.state.isInitialized, isTrue);
        expect(bloc.state.currentPath, '/');
        expect(bloc.state.stack.length, 1);
      });

      test('withConfig factory initializes automatically', () async {
        bloc = RoutingBloc.withConfig(config);

        // Wait for event processing
        await Future.delayed(const Duration(milliseconds: 50));

        expect(bloc.state.isInitialized, isTrue);
        expect(bloc.state.currentPath, '/');
      });

      test('can override initial path', () async {
        bloc = RoutingBloc.withConfig(config, initialPath: '/settings');

        // Wait for event processing
        await Future.delayed(const Duration(milliseconds: 50));

        expect(bloc.state.currentPath, '/settings');
      });
    });

    group('navigation', () {
      setUp(() async {
        bloc = RoutingBloc.withConfig(config);
        await Future.delayed(const Duration(milliseconds: 50));
      });

      test('push adds to stack', () async {
        bloc.navigate('/settings');

        await Future.delayed(const Duration(milliseconds: 50));

        expect(bloc.state.stack.length, 2);
        expect(bloc.state.currentPath, '/settings');
      });

      test('push with params extracts parameters', () async {
        bloc.navigate('/profile/123');

        await Future.delayed(const Duration(milliseconds: 50));

        expect(bloc.state.currentPath, '/profile/123');
        expect(bloc.state.current!.params['userId'], '123');
      });

      test('replace replaces top entry', () async {
        bloc.navigate('/settings');
        await Future.delayed(const Duration(milliseconds: 50));
        expect(bloc.state.stack.length, 2);

        bloc.navigate('/profile/456', replace: true);
        await Future.delayed(const Duration(milliseconds: 50));

        expect(bloc.state.stack.length, 2);
        expect(bloc.state.currentPath, '/profile/456');
      });

      test('extra data is passed to route', () async {
        final extraData = {'key': 'value'};
        bloc.navigate('/settings', extra: extraData);

        await Future.delayed(const Duration(milliseconds: 50));

        expect(bloc.state.current!.extra, extraData);
      });
    });

    group('pop operations', () {
      setUp(() async {
        bloc = RoutingBloc.withConfig(config);
        await Future.delayed(const Duration(milliseconds: 50));
        bloc.navigate('/settings');
        await Future.delayed(const Duration(milliseconds: 50));
        bloc.navigate('/profile/123');
        await Future.delayed(const Duration(milliseconds: 50));
      });

      test('pop removes top entry', () async {
        expect(bloc.state.stack.length, 3);

        bloc.pop();
        await Future.delayed(const Duration(milliseconds: 50));

        expect(bloc.state.stack.length, 2);
        expect(bloc.state.currentPath, '/settings');
      });

      test('popToRoot leaves only first entry', () async {
        expect(bloc.state.stack.length, 3);

        bloc.popToRoot();
        await Future.delayed(const Duration(milliseconds: 50));

        expect(bloc.state.stack.length, 1);
        expect(bloc.state.currentPath, '/');
      });

      test('popUntil pops until predicate matches', () async {
        bloc.popUntil((entry) => entry.path == '/settings');
        await Future.delayed(const Duration(milliseconds: 50));

        expect(bloc.state.stack.length, 2);
        expect(bloc.state.currentPath, '/settings');
      });

      test('canPop returns true when stack has multiple entries', () async {
        expect(bloc.state.canPop, isTrue);
      });

      test('canPop returns false at root', () async {
        bloc.popToRoot();
        await Future.delayed(const Duration(milliseconds: 50));

        expect(bloc.state.canPop, isFalse);
      });
    });

    group('resetStack', () {
      setUp(() async {
        bloc = RoutingBloc.withConfig(config);
        await Future.delayed(const Duration(milliseconds: 50));
        bloc.navigate('/settings');
        await Future.delayed(const Duration(milliseconds: 50));
      });

      test('replaces entire stack with single entry', () async {
        expect(bloc.state.stack.length, 2);

        bloc.resetStack('/profile/999');
        await Future.delayed(const Duration(milliseconds: 50));

        expect(bloc.state.stack.length, 1);
        expect(bloc.state.currentPath, '/profile/999');
        expect(bloc.state.current!.params['userId'], '999');
      });
    });

    group('history tracking', () {
      test('records navigation history', () async {
        bloc = RoutingBloc.withConfig(config);
        await Future.delayed(const Duration(milliseconds: 50));

        bloc.navigate('/settings');
        await Future.delayed(const Duration(milliseconds: 50));

        bloc.navigate('/profile/123');
        await Future.delayed(const Duration(milliseconds: 50));

        // Initial + 2 navigations
        expect(bloc.state.history.length, 3);
        expect(bloc.state.history[0].path, '/');
        expect(bloc.state.history[0].type, NavigationType.push);
        expect(bloc.state.history[1].path, '/settings');
        expect(bloc.state.history[2].path, '/profile/123');
      });

      test('records pop in history', () async {
        bloc = RoutingBloc.withConfig(config);
        await Future.delayed(const Duration(milliseconds: 50));

        bloc.navigate('/settings');
        await Future.delayed(const Duration(milliseconds: 50));

        bloc.pop();
        await Future.delayed(const Duration(milliseconds: 50));

        expect(bloc.state.history.last.type, NavigationType.pop);
        expect(bloc.state.history.last.path, '/settings');
      });
    });

    group('error handling', () {
      test('sets error for unknown route', () async {
        bloc = RoutingBloc.withConfig(config);
        await Future.delayed(const Duration(milliseconds: 50));

        bloc.navigate('/unknown');
        await Future.delayed(const Duration(milliseconds: 50));

        expect(bloc.state.error, isA<RouteNotFoundError>());
      });

      test('sets error when popping at root', () async {
        bloc = RoutingBloc.withConfig(config);
        await Future.delayed(const Duration(milliseconds: 50));

        bloc.pop();
        await Future.delayed(const Duration(milliseconds: 50));

        expect(bloc.state.error, isA<CannotPopError>());
      });
    });

    group('stack entry keys', () {
      test('each entry has unique key', () async {
        bloc = RoutingBloc.withConfig(config);
        await Future.delayed(const Duration(milliseconds: 50));

        bloc.navigate('/settings');
        await Future.delayed(const Duration(milliseconds: 50));

        bloc.navigate('/profile/123');
        await Future.delayed(const Duration(milliseconds: 50));

        final keys = bloc.state.stack.map((e) => e.key).toSet();
        expect(keys.length, bloc.state.stack.length);
      });
    });

    group('maxHistorySize', () {
      test('trims oldest history entries when limit exceeded', () async {
        final smallHistoryConfig = RoutingConfig(
          routes: [
            RouteConfig(path: '/', builder: (_) => const SizedBox()),
            RouteConfig(path: '/settings', builder: (_) => const SizedBox()),
            RouteConfig(
                path: '/profile/:userId', builder: (_) => const SizedBox()),
          ],
          initialPath: '/',
          maxHistorySize: 3,
        );
        bloc = RoutingBloc.withConfig(smallHistoryConfig);
        await Future.delayed(const Duration(milliseconds: 50));

        // History: [/ (push)] — 1 entry
        expect(bloc.state.history.length, 1);

        bloc.navigate('/settings');
        await Future.delayed(const Duration(milliseconds: 50));
        // History: [/ (push), /settings (push)] — 2 entries
        expect(bloc.state.history.length, 2);

        bloc.navigate('/profile/1');
        await Future.delayed(const Duration(milliseconds: 50));
        // History: [/ (push), /settings (push), /profile/1 (push)] — 3 entries (at limit)
        expect(bloc.state.history.length, 3);

        bloc.navigate('/settings', replace: true);
        await Future.delayed(const Duration(milliseconds: 50));
        // Would be 4, trimmed to 3 — oldest entry (/) removed
        expect(bloc.state.history.length, 3);
        expect(bloc.state.history.first.path, '/settings');
      });

      test('trims history on pop operations', () async {
        final smallHistoryConfig = RoutingConfig(
          routes: [
            RouteConfig(path: '/', builder: (_) => const SizedBox()),
            RouteConfig(path: '/settings', builder: (_) => const SizedBox()),
            RouteConfig(
                path: '/profile/:userId', builder: (_) => const SizedBox()),
          ],
          initialPath: '/',
          maxHistorySize: 4,
        );
        bloc = RoutingBloc.withConfig(smallHistoryConfig);
        await Future.delayed(const Duration(milliseconds: 50));

        bloc.navigate('/settings');
        await Future.delayed(const Duration(milliseconds: 50));
        bloc.navigate('/profile/1');
        await Future.delayed(const Duration(milliseconds: 50));
        // 3 entries: / push, /settings push, /profile/1 push

        bloc.pop();
        await Future.delayed(const Duration(milliseconds: 50));
        // 4 entries: / push, /settings push, /profile/1 push, /profile/1 pop — at limit
        expect(bloc.state.history.length, 4);

        bloc.pop();
        await Future.delayed(const Duration(milliseconds: 50));
        // Would be 5, trimmed to 4
        expect(bloc.state.history.length, 4);
        // Oldest (/ push) trimmed
        expect(bloc.state.history.first.path, '/settings');
      });
    });

    group('navigation queuing', () {
      test('latest navigation wins when concurrent', () async {
        final slowGuardConfig = RoutingConfig(
          routes: [
            RouteConfig(path: '/', builder: (_) => const SizedBox()),
            RouteConfig(
              path: '/slow',
              builder: (_) => const SizedBox(),
              guards: [_SlowGuard()],
            ),
            RouteConfig(path: '/settings', builder: (_) => const SizedBox()),
            RouteConfig(
                path: '/profile/:userId', builder: (_) => const SizedBox()),
          ],
          initialPath: '/',
        );
        bloc = RoutingBloc.withConfig(slowGuardConfig);
        await Future.delayed(const Duration(milliseconds: 50));

        // Start a slow navigation — will be pending
        bloc.navigate('/slow');
        await Future.delayed(const Duration(milliseconds: 10));
        expect(bloc.state.isNavigating, isTrue);

        // Queue two more — only the latest should win
        bloc.navigate('/settings');
        bloc.navigate('/profile/42');

        // Wait for slow guard + queued processing
        await Future.delayed(const Duration(milliseconds: 300));

        expect(bloc.state.currentPath, '/profile/42');
      });
    });

    group('resetStack with guards', () {
      test('resetStack redirects when guard redirects', () async {
        final guardConfig = RoutingConfig(
          routes: [
            RouteConfig(path: '/', builder: (_) => const SizedBox()),
            RouteConfig(path: '/login', builder: (_) => const SizedBox()),
            RouteConfig(
              path: '/dashboard',
              builder: (_) => const SizedBox(),
              guards: [_RedirectToLoginGuard()],
            ),
          ],
        );
        bloc = RoutingBloc.withConfig(guardConfig);
        await Future.delayed(const Duration(milliseconds: 50));

        bloc.resetStack('/dashboard');
        await Future.delayed(const Duration(milliseconds: 100));

        // Guard redirected to /login, resetStack should follow the redirect
        expect(bloc.state.currentPath, '/login');
        expect(bloc.state.stack.length, 1);
      });

      test('resetStack blocks when guard blocks', () async {
        final guardConfig = RoutingConfig(
          routes: [
            RouteConfig(path: '/', builder: (_) => const SizedBox()),
            RouteConfig(
              path: '/admin',
              builder: (_) => const SizedBox(),
              guards: [_BlockGuard()],
            ),
          ],
        );
        bloc = RoutingBloc.withConfig(guardConfig);
        await Future.delayed(const Duration(milliseconds: 50));

        bloc.resetStack('/admin');
        await Future.delayed(const Duration(milliseconds: 50));

        expect(bloc.state.currentPath, '/'); // Still at root
        expect(bloc.state.error, isA<GuardBlockedError>());
      });
    });
  });
}

class _SlowGuard extends RouteGuard {
  @override
  String get name => 'SlowGuard';

  @override
  Future<GuardResult> check(RouteContext context) async {
    await Future.delayed(const Duration(milliseconds: 100));
    return const GuardResult.allow();
  }
}

class _RedirectToLoginGuard extends RouteGuard {
  @override
  String get name => 'RedirectToLoginGuard';

  @override
  Future<GuardResult> check(RouteContext context) async {
    return const GuardResult.redirect('/login');
  }
}

class _BlockGuard extends RouteGuard {
  @override
  String get name => 'BlockGuard';

  @override
  Future<GuardResult> check(RouteContext context) async {
    return const GuardResult.block(reason: 'Access denied');
  }
}
