import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_routing/juice_routing.dart';

// Test guards
class AllowGuard extends RouteGuard {
  @override
  String get name => 'AllowGuard';

  @override
  Future<GuardResult> check(RouteContext context) async {
    return const GuardResult.allow();
  }
}

class BlockGuard extends RouteGuard {
  final String? blockReason;

  BlockGuard({this.blockReason});

  @override
  String get name => 'BlockGuard';

  @override
  Future<GuardResult> check(RouteContext context) async {
    return GuardResult.block(reason: blockReason);
  }
}

class RedirectGuard extends RouteGuard {
  final String redirectPath;

  RedirectGuard(this.redirectPath);

  @override
  String get name => 'RedirectGuard';

  @override
  Future<GuardResult> check(RouteContext context) async {
    return GuardResult.redirect(redirectPath);
  }
}

class ConditionalGuard extends RouteGuard {
  final bool Function() condition;
  final String redirectPath;

  ConditionalGuard({
    required this.condition,
    required this.redirectPath,
  });

  @override
  String get name => 'ConditionalGuard';

  @override
  Future<GuardResult> check(RouteContext context) async {
    if (condition()) {
      return const GuardResult.allow();
    }
    return GuardResult.redirect(redirectPath);
  }
}

/// Allows, after a delay: holds a navigation pending for [delay].
class SlowAllowGuard extends RouteGuard {
  final Duration delay;

  SlowAllowGuard(this.delay);

  @override
  String get name => 'SlowAllowGuard';

  @override
  Future<GuardResult> check(RouteContext context) async {
    await Future<void>.delayed(delay);
    return const GuardResult.allow();
  }
}

class ThrowingGuard extends RouteGuard {
  @override
  String get name => 'ThrowingGuard';

  @override
  Future<GuardResult> check(RouteContext context) async {
    throw Exception('Guard error');
  }
}

class OrderTrackingGuard extends RouteGuard {
  final List<String> executionLog;
  final String guardId;
  final int guardPriority;

  OrderTrackingGuard({
    required this.executionLog,
    required this.guardId,
    this.guardPriority = 100,
  });

  @override
  String get name => 'OrderTrackingGuard:$guardId';

  @override
  int get priority => guardPriority;

  @override
  Future<GuardResult> check(RouteContext context) async {
    executionLog.add(guardId);
    return const GuardResult.allow();
  }
}

void main() {
  group('Route Guards', () {
    late RoutingBloc bloc;

    tearDown(() async {
      await bloc.close();
    });

    group('allow behavior', () {
      test('allows navigation when guard returns allow', () async {
        final config = RoutingConfig(
          routes: [
            RouteConfig(path: '/', builder: (_) => const SizedBox()),
            RouteConfig(
              path: '/protected',
              builder: (_) => const SizedBox(),
              guards: [AllowGuard()],
            ),
          ],
        );
        bloc = RoutingBloc.withConfig(config);
        await Future.delayed(const Duration(milliseconds: 50));

        bloc.navigate('/protected');
        await Future.delayed(const Duration(milliseconds: 50));

        expect(bloc.state.currentPath, '/protected');
        expect(bloc.state.error, isNull);
      });
    });

    group('block behavior', () {
      test('blocks navigation when guard returns block', () async {
        final config = RoutingConfig(
          routes: [
            RouteConfig(path: '/', builder: (_) => const SizedBox()),
            RouteConfig(
              path: '/protected',
              builder: (_) => const SizedBox(),
              guards: [BlockGuard()],
            ),
          ],
        );
        bloc = RoutingBloc.withConfig(config);
        await Future.delayed(const Duration(milliseconds: 50));

        bloc.navigate('/protected');
        await Future.delayed(const Duration(milliseconds: 50));

        expect(bloc.state.currentPath, '/'); // Still at root
        expect(bloc.state.error, isA<GuardBlockedError>());
      });

      test('includes block reason in error', () async {
        final config = RoutingConfig(
          routes: [
            RouteConfig(path: '/', builder: (_) => const SizedBox()),
            RouteConfig(
              path: '/protected',
              builder: (_) => const SizedBox(),
              guards: [BlockGuard(blockReason: 'Not authorized')],
            ),
          ],
        );
        bloc = RoutingBloc.withConfig(config);
        await Future.delayed(const Duration(milliseconds: 50));

        bloc.navigate('/protected');
        await Future.delayed(const Duration(milliseconds: 50));

        final error = bloc.state.error as GuardBlockedError;
        expect(error.reason, 'Not authorized');
      });
    });

    group('redirect behavior', () {
      test('redirects when guard returns redirect', () async {
        final config = RoutingConfig(
          routes: [
            RouteConfig(path: '/', builder: (_) => const SizedBox()),
            RouteConfig(path: '/login', builder: (_) => const SizedBox()),
            RouteConfig(
              path: '/protected',
              builder: (_) => const SizedBox(),
              guards: [RedirectGuard('/login')],
            ),
          ],
        );
        bloc = RoutingBloc.withConfig(config);
        await Future.delayed(const Duration(milliseconds: 50));

        bloc.navigate('/protected');
        await Future.delayed(const Duration(milliseconds: 100));

        expect(bloc.state.currentPath, '/login');
        expect(bloc.state.error, isNull);
      });

      test('conditional guard redirects based on condition', () async {
        var isLoggedIn = false;

        final config = RoutingConfig(
          routes: [
            RouteConfig(path: '/', builder: (_) => const SizedBox()),
            RouteConfig(path: '/login', builder: (_) => const SizedBox()),
            RouteConfig(
              path: '/dashboard',
              builder: (_) => const SizedBox(),
              guards: [
                ConditionalGuard(
                  condition: () => isLoggedIn,
                  redirectPath: '/login',
                ),
              ],
            ),
          ],
        );
        bloc = RoutingBloc.withConfig(config);
        await Future.delayed(const Duration(milliseconds: 50));

        // Not logged in - should redirect
        bloc.navigate('/dashboard');
        await Future.delayed(const Duration(milliseconds: 100));
        expect(bloc.state.currentPath, '/login');

        // Log in and try again
        isLoggedIn = true;
        bloc.navigate('/dashboard');
        await Future.delayed(const Duration(milliseconds: 100));
        expect(bloc.state.currentPath, '/dashboard');
      });
    });

    group('redirect loop protection', () {
      test('detects redirect loop and emits error', () async {
        final config = RoutingConfig(
          routes: [
            RouteConfig(path: '/', builder: (_) => const SizedBox()),
            RouteConfig(
              path: '/a',
              builder: (_) => const SizedBox(),
              guards: [RedirectGuard('/b')],
            ),
            RouteConfig(
              path: '/b',
              builder: (_) => const SizedBox(),
              guards: [RedirectGuard('/a')], // Creates loop
            ),
          ],
          maxRedirects: 5,
        );
        bloc = RoutingBloc.withConfig(config);
        await Future.delayed(const Duration(milliseconds: 50));

        bloc.navigate('/a');
        await Future.delayed(const Duration(milliseconds: 200));

        expect(bloc.state.error, isA<RedirectLoopError>());
      });

      test('populates redirectChain with actual paths', () async {
        final config = RoutingConfig(
          routes: [
            RouteConfig(path: '/', builder: (_) => const SizedBox()),
            RouteConfig(
              path: '/a',
              builder: (_) => const SizedBox(),
              guards: [RedirectGuard('/b')],
            ),
            RouteConfig(
              path: '/b',
              builder: (_) => const SizedBox(),
              guards: [RedirectGuard('/c')],
            ),
            RouteConfig(
              path: '/c',
              builder: (_) => const SizedBox(),
              guards: [RedirectGuard('/a')], // Creates loop back to /a
            ),
          ],
          maxRedirects: 3,
        );
        bloc = RoutingBloc.withConfig(config);
        await Future.delayed(const Duration(milliseconds: 50));

        bloc.navigate('/a');
        await Future.delayed(const Duration(milliseconds: 200));

        expect(bloc.state.error, isA<RedirectLoopError>());
        final error = bloc.state.error as RedirectLoopError;
        // Chain: started at /a, redirected to /b, /c, /a (loop detected at limit 3)
        expect(error.redirectChain, ['/a', '/b', '/c', '/a']);
      });
    });

    group('guard exceptions', () {
      test('captures guard exception as error', () async {
        final config = RoutingConfig(
          routes: [
            RouteConfig(path: '/', builder: (_) => const SizedBox()),
            RouteConfig(
              path: '/protected',
              builder: (_) => const SizedBox(),
              guards: [ThrowingGuard()],
            ),
          ],
        );
        bloc = RoutingBloc.withConfig(config);
        await Future.delayed(const Duration(milliseconds: 50));

        bloc.navigate('/protected');
        await Future.delayed(const Duration(milliseconds: 50));

        expect(bloc.state.currentPath, '/'); // Still at root
        expect(bloc.state.error, isA<GuardExceptionError>());
        final error = bloc.state.error as GuardExceptionError;
        expect(error.guardName, 'ThrowingGuard');
      });
    });

    group('guard execution order', () {
      test('guards execute in priority order', () async {
        final executionLog = <String>[];

        final config = RoutingConfig(
          routes: [
            RouteConfig(path: '/', builder: (_) => const SizedBox()),
            RouteConfig(
              path: '/protected',
              builder: (_) => const SizedBox(),
              guards: [
                OrderTrackingGuard(
                  executionLog: executionLog,
                  guardId: 'low',
                  guardPriority: 200,
                ),
                OrderTrackingGuard(
                  executionLog: executionLog,
                  guardId: 'high',
                  guardPriority: 50,
                ),
                OrderTrackingGuard(
                  executionLog: executionLog,
                  guardId: 'mid',
                  guardPriority: 100,
                ),
              ],
            ),
          ],
        );
        bloc = RoutingBloc.withConfig(config);
        await Future.delayed(const Duration(milliseconds: 50));

        bloc.navigate('/protected');
        await Future.delayed(const Duration(milliseconds: 50));

        expect(executionLog, ['high', 'mid', 'low']);
      });

      test('global guards run before route guards', () async {
        final executionLog = <String>[];

        final config = RoutingConfig(
          routes: [
            RouteConfig(path: '/', builder: (_) => const SizedBox()),
            RouteConfig(
              path: '/protected',
              builder: (_) => const SizedBox(),
              guards: [
                OrderTrackingGuard(
                  executionLog: executionLog,
                  guardId: 'route',
                  guardPriority: 50, // Even with higher priority
                ),
              ],
            ),
          ],
          globalGuards: [
            OrderTrackingGuard(
              executionLog: executionLog,
              guardId: 'global',
              guardPriority: 100, // Lower priority than route guard
            ),
          ],
        );
        bloc = RoutingBloc.withConfig(config);
        await Future.delayed(const Duration(milliseconds: 50));

        // The initial path '/' is guarded too: the global guard has run once.
        expect(executionLog, ['global']);
        executionLog.clear();

        bloc.navigate('/protected');
        await Future.delayed(const Duration(milliseconds: 50));

        // Global guards are added first, then sorted together
        // So with global=100 and route=50, route runs first
        expect(executionLog, ['route', 'global']);
      });
    });

    group('initial path', () {
      Future<void> settle() =>
          Future<void>.delayed(const Duration(milliseconds: 50));

      RouteConfig route(String path, [List<RouteGuard> guards = const []]) =>
          RouteConfig(
              path: path, builder: (_) => const SizedBox(), guards: guards);

      test('an allowed initial path is seeded', () async {
        bloc = RoutingBloc.withConfig(RoutingConfig(routes: [
          route('/', [AllowGuard()]),
        ]));
        await settle();

        expect(bloc.state.isInitialized, isTrue);
        expect(bloc.state.stack.length, 1);
        expect(bloc.state.currentPath, '/');
        expect(bloc.state.isNavigating, isFalse);
        expect(bloc.state.error, isNull);
      });

      test('a route guard redirects the initial path', () async {
        bloc = RoutingBloc.withConfig(RoutingConfig(routes: [
          route('/', [RedirectGuard('/login')]),
          route('/login'),
        ]));
        await settle();

        expect(bloc.state.isInitialized, isTrue);
        expect(bloc.state.stack.length, 1);
        expect(bloc.state.currentPath, '/login');
        expect(bloc.state.isNavigating, isFalse);
      });

      test('a global guard runs on the initial path', () async {
        var authenticated = false;
        bloc = RoutingBloc.withConfig(RoutingConfig(
          routes: [route('/'), route('/login')],
          globalGuards: [
            _LoginWall(() => authenticated),
          ],
        ));
        await settle();

        expect(bloc.state.stack.length, 1);
        expect(bloc.state.currentPath, '/login');

        authenticated = true;
        bloc.resetStack('/');
        await settle();
        expect(bloc.state.currentPath, '/');
      });

      test('the redirect target of the initial path is guarded in turn',
          () async {
        bloc = RoutingBloc.withConfig(RoutingConfig(routes: [
          route('/', [RedirectGuard('/a')]),
          route('/a', [RedirectGuard('/b')]),
          route('/b'),
        ]));
        await settle();

        expect(bloc.state.stack.length, 1);
        expect(bloc.state.currentPath, '/b');
      });

      test('an overridden initial path is guarded', () async {
        bloc = RoutingBloc.withConfig(
          RoutingConfig(routes: [
            route('/'),
            route('/admin', [RedirectGuard('/')]),
          ]),
          initialPath: '/admin',
        );
        await settle();

        expect(bloc.state.stack.length, 1);
        expect(bloc.state.currentPath, '/');
      });

      test('a blocked initial path seeds nothing and reports the block',
          () async {
        bloc = RoutingBloc.withConfig(RoutingConfig(routes: [
          route('/', [BlockGuard(blockReason: 'closed')]),
        ]));
        await settle();

        expect(bloc.state.stack, isEmpty);
        expect(bloc.state.isInitialized, isTrue);
        expect(bloc.state.isNavigating, isFalse);
        final error = bloc.state.error;
        expect(error, isA<GuardBlockedError>());
        expect((error as GuardBlockedError).path, '/');
        expect(error.reason, 'closed');
      });

      test('a guard that throws on the initial path seeds nothing', () async {
        bloc = RoutingBloc.withConfig(RoutingConfig(routes: [
          route('/', [ThrowingGuard()]),
        ]));
        await settle();

        expect(bloc.state.stack, isEmpty);
        expect(bloc.state.isInitialized, isTrue);
        expect(bloc.state.isNavigating, isFalse);
        expect(bloc.state.error, isA<GuardExceptionError>());
      });

      test('a redirect loop from the initial path seeds nothing', () async {
        bloc = RoutingBloc.withConfig(RoutingConfig(routes: [
          route('/', [RedirectGuard('/b')]),
          route('/b', [RedirectGuard('/')]),
        ]));
        await Future<void>.delayed(const Duration(milliseconds: 200));

        expect(bloc.state.stack, isEmpty);
        expect(bloc.state.isInitialized, isTrue);
        expect(bloc.state.isNavigating, isFalse);
        expect(bloc.state.error, isA<RedirectLoopError>());
      });

      test('an unknown redirect target from the initial path seeds nothing',
          () async {
        bloc = RoutingBloc.withConfig(RoutingConfig(routes: [
          route('/', [RedirectGuard('/nowhere')]),
        ]));
        await settle();

        expect(bloc.state.stack, isEmpty);
        expect(bloc.state.isInitialized, isTrue);
        expect(bloc.state.isNavigating, isFalse);
        expect(bloc.state.error, isA<RouteNotFoundError>());
      });

      test('a navigation sent while the initial guards run follows the seed',
          () async {
        bloc = RoutingBloc.withConfig(RoutingConfig(routes: [
          route('/', [SlowAllowGuard(const Duration(milliseconds: 40))]),
          route('/settings'),
        ]));
        await Future<void>.delayed(const Duration(milliseconds: 10));
        expect(bloc.state.isNavigating, isTrue); // the guard is still running
        expect(bloc.state.stack, isEmpty);

        bloc.navigate('/settings');
        await Future<void>.delayed(const Duration(milliseconds: 120));

        expect(bloc.state.stack.map((e) => e.path), ['/', '/settings']);
        expect(bloc.state.isNavigating, isFalse);
      });

      test(
          'the cold-start report of a redirected initial path does not push '
          'the redirect target a second time', () async {
        bloc = RoutingBloc.withConfig(RoutingConfig(routes: [
          route('/', [AuthGuard(isAuthenticated: () => false)]),
          route('/login'),
        ]));
        // No pre-wait: the report races initialization, as on a real launch.
        bloc.send(NavigateEvent(path: '/', fromPlatform: true));
        await settle();

        expect(bloc.state.stack.length, 1);
        expect(bloc.state.currentPath, '/login');
        expect(bloc.state.current!.query['returnTo'], '/');
        expect(bloc.state.isNavigating, isFalse);
      });

      test('a late cold-start report of a redirected initial path is the same',
          () async {
        bloc = RoutingBloc.withConfig(RoutingConfig(routes: [
          route('/', [AuthGuard(isAuthenticated: () => false)]),
          route('/login'),
        ]));
        await settle();
        final seeded = bloc.state.current!.key;

        bloc.send(NavigateEvent(path: '/', fromPlatform: true));
        await settle();

        expect(bloc.state.stack.length, 1);
        expect(bloc.state.current!.key, seeded); // the entry was not rebuilt
        expect(bloc.state.isNavigating, isFalse);
      });
    });

    group('returnTo', () {
      Future<void> settle() =>
          Future<void>.delayed(const Duration(milliseconds: 50));

      late bool authenticated;

      RoutingConfig config() => RoutingConfig(routes: [
            RouteConfig(path: '/', builder: (_) => const SizedBox()),
            RouteConfig(
              path: '/login',
              builder: (_) => const SizedBox(),
              guards: [GuestGuard(isAuthenticated: () => authenticated)],
            ),
            RouteConfig(
              path: '/profile/:userId',
              builder: (_) => const SizedBox(),
              guards: [AuthGuard(isAuthenticated: () => authenticated)],
            ),
            RouteConfig(
              path: '/search',
              builder: (_) => const SizedBox(),
              guards: [AuthGuard(isAuthenticated: () => authenticated)],
            ),
          ]);

      setUp(() => authenticated = false);

      test('a redirect carries returnTo as a query parameter', () async {
        bloc = RoutingBloc.withConfig(config());
        await settle();

        bloc.navigate('/profile/123');
        await settle();

        expect(bloc.state.currentPath, '/login');
        expect(bloc.state.current!.query['returnTo'], '/profile/123');
        expect(bloc.state.stack.length, 2);
      });

      test('a returnTo that has its own query survives the round trip',
          () async {
        bloc = RoutingBloc.withConfig(config());
        await settle();

        bloc.navigate('/search?q=a%20b&page=2');
        await settle();

        expect(bloc.state.currentPath, '/login');
        final returnTo = bloc.state.current!.query['returnTo'];
        expect(returnTo, '/search?q=a%20b&page=2');

        authenticated = true;
        bloc.navigate(returnTo!, replace: true);
        await settle();
        expect(bloc.state.currentPath, '/search');
        expect(bloc.state.current!.query, {'q': 'a b', 'page': '2'});
      });

      test('resetStack carries returnTo the same way', () async {
        bloc = RoutingBloc.withConfig(config());
        await settle();

        bloc.resetStack('/profile/7');
        await settle();

        expect(bloc.state.stack.length, 1);
        expect(bloc.state.currentPath, '/login');
        expect(bloc.state.current!.query['returnTo'], '/profile/7');
      });

      test('a redirect without returnTo adds no query parameter', () async {
        authenticated = true;
        bloc = RoutingBloc.withConfig(RoutingConfig(routes: [
          RouteConfig(path: '/', builder: (_) => const SizedBox()),
          RouteConfig(
            path: '/old',
            builder: (_) => const SizedBox(),
            guards: [RedirectGuard('/new?tab=a')],
          ),
          RouteConfig(path: '/new', builder: (_) => const SizedBox()),
        ]));
        await settle();

        bloc.navigate('/old');
        await settle();

        expect(bloc.state.currentPath, '/new');
        expect(bloc.state.current!.query, {'tab': 'a'});
      });

      test('the login flow resumes the captured destination', () async {
        bloc = RoutingBloc.withConfig(config());
        await settle();
        bloc.navigate('/profile/123');
        await settle();

        authenticated = true;
        bloc.navigate(bloc.state.current!.query['returnTo']!, replace: true);
        await settle();

        expect(bloc.state.stack.map((e) => e.path), ['/', '/profile/123']);
        expect(bloc.state.current!.params['userId'], '123');
      });

      test(
          'a second redirect onto the page already on top replaces it with '
          'the newer returnTo', () async {
        bloc = RoutingBloc.withConfig(config());
        await settle();
        bloc.navigate('/profile/1');
        await settle();
        expect(bloc.state.stack.length, 2);

        bloc.navigate('/profile/2');
        await settle();

        expect(bloc.state.stack.map((e) => e.path), ['/', '/login']);
        expect(bloc.state.current!.query['returnTo'], '/profile/2');
        expect(bloc.state.isNavigating, isFalse);
      });

      test('a redirect onto the current location changes nothing', () async {
        authenticated = true;
        bloc = RoutingBloc.withConfig(config());
        await settle();
        final home = bloc.state.current!.key;

        bloc.navigate('/login'); // the guest guard sends it back to '/'
        await settle();

        expect(bloc.state.stack.length, 1);
        expect(bloc.state.current!.key, home);
        expect(bloc.state.isNavigating, isFalse);
        expect(bloc.state.error, isNull);
      });
    });

    group('pop bypasses guards', () {
      test('pop does not run guards', () async {
        var guardCalled = false;

        final config = RoutingConfig(
          routes: [
            RouteConfig(path: '/', builder: (_) => const SizedBox()),
            RouteConfig(
              path: '/protected',
              builder: (_) => const SizedBox(),
              guards: [
                AllowGuard(), // Mark navigation as guarded
              ],
            ),
          ],
          globalGuards: [
            // Global guard that tracks calls
            _CallTrackingGuard(() => guardCalled = true),
          ],
        );
        bloc = RoutingBloc.withConfig(config);
        await Future.delayed(const Duration(milliseconds: 50));

        bloc.navigate('/protected');
        await Future.delayed(const Duration(milliseconds: 50));
        expect(guardCalled, isTrue);

        // Reset tracking
        guardCalled = false;

        // Pop should NOT call guards
        bloc.pop();
        await Future.delayed(const Duration(milliseconds: 50));

        expect(bloc.state.currentPath, '/');
        expect(guardCalled, isFalse);
      });
    });
  });
}

/// Redirects every path but /login to /login until authenticated.
class _LoginWall extends RouteGuard {
  final bool Function() isAuthenticated;

  _LoginWall(this.isAuthenticated);

  @override
  String get name => '_LoginWall';

  @override
  Future<GuardResult> check(RouteContext context) async {
    if (isAuthenticated() || context.targetPath == '/login') {
      return const GuardResult.allow();
    }
    return const GuardResult.redirect('/login');
  }
}

class _CallTrackingGuard extends RouteGuard {
  final void Function() onCheck;

  _CallTrackingGuard(this.onCheck);

  @override
  String get name => 'CallTrackingGuard';

  @override
  Future<GuardResult> check(RouteContext context) async {
    onCheck();
    return const GuardResult.allow();
  }
}
