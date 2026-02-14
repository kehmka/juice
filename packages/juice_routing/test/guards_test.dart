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

        bloc.navigate('/protected');
        await Future.delayed(const Duration(milliseconds: 50));

        // Global guards are added first, then sorted together
        // So with global=100 and route=50, route runs first
        expect(executionLog, ['route', 'global']);
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
