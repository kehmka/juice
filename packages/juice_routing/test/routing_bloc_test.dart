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
  });
}
