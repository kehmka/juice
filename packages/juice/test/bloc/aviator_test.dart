import 'package:flutter_test/flutter_test.dart';
import 'package:juice/juice.dart';
import 'package:juice/src/bloc/src/core/aviator_manager.dart';

/// Pins for the aviator (navigation) system: `Aviator`, `DeepLinkAviator`,
/// `AviatorManager`, and the use-case → aviator wiring through `JuiceBloc`.

class _ClosingAviator extends AviatorBase {
  _ClosingAviator(this.name, this.log);
  @override
  final String name;
  final List<String> log;
  @override
  NavigateWhere get navigateWhere => (args) => log.add('$name:$args');
  @override
  Future<void> close() async => log.add('close:$name');
}

/// Relies on `AviatorBase.close`'s default (no-op) implementation.
class _PlainAviator extends AviatorBase {
  @override
  String get name => 'plain';
  @override
  NavigateWhere get navigateWhere => (_) {};
}

class _S extends BlocState {
  const _S();
}

class _Go extends EventBase {
  final String? to;
  final bool fail;
  _Go(this.to, {this.fail = false});
}

class _GoUC extends BlocUseCase<_B, _Go> {
  @override
  Future<void> execute(_Go e) async {
    if (e.fail) {
      emitFailure(aviatorName: e.to, aviatorArgs: {'why': 'fail'});
    } else {
      emitUpdate(aviatorName: e.to, aviatorArgs: {'id': 7});
    }
  }
}

class _B extends JuiceBloc<_S> {
  _B(List<AviatorBuilder> aviators)
      : super(
          const _S(),
          [
            () => UseCaseBuilder(
                typeOfEvent: _Go, useCaseGenerator: () => _GoUC()),
          ],
          aviators,
        );
}

void main() {
  group('Aviator', () {
    test('exposes name and navigateWhere; close is a no-op', () async {
      final got = <Map<String, dynamic>>[];
      final a = Aviator(name: 'home', navigateWhere: got.add);
      expect(a.name, 'home');
      await a.navigateWhere({'x': 1});
      expect(got, [
        {'x': 1}
      ]);
      await a.close();
    });
  });

  group('AviatorManager', () {
    test('register / lookup / replace by name', () {
      final m = AviatorManager();
      expect(m.aviatorCount, 0);
      m.register(Aviator(name: 'a', navigateWhere: (_) {}));
      m.register(Aviator(name: 'b', navigateWhere: (_) {}));
      m.register(Aviator(name: 'a', navigateWhere: (_) {}));
      expect(m.aviatorCount, 2);
      expect(m.hasAviator('a'), isTrue);
      expect(m.hasAviator('zzz'), isFalse);
      expect(m.aviatorNames, unorderedEquals(['a', 'b']));
    });

    test('navigate invokes the named aviator; null args become {}', () {
      final got = <Map<String, dynamic>>[];
      final m = AviatorManager()
        ..register(Aviator(name: 'a', navigateWhere: got.add));
      m.navigate('a', {'k': 'v'});
      m.navigate('a', null);
      expect(got, [
        {'k': 'v'},
        <String, dynamic>{}
      ]);
    });

    test('navigate with null or unknown name is a no-op', () {
      var hits = 0;
      final m = AviatorManager()
        ..register(Aviator(name: 'a', navigateWhere: (_) => hits++));
      m.navigate(null, {'x': 1});
      m.navigate('missing', {'x': 1});
      expect(hits, 0);
    });

    test('navigateAsync awaits async navigation', () async {
      final log = <String>[];
      final m = AviatorManager()
        ..register(Aviator(
            name: 'slow',
            navigateWhere: (args) async {
              await Future<void>.delayed(const Duration(milliseconds: 5));
              log.add('done:${args['n']}');
            }));
      await m.navigateAsync('slow', {'n': 1});
      expect(log, ['done:1']);
      await m.navigateAsync('slow', null);
      expect(log, ['done:1', 'done:null']);
      await m.navigateAsync(null, {'n': 2});
      await m.navigateAsync('missing', {'n': 3});
      expect(log, hasLength(2));
    });

    test('navigateAsync propagates navigation errors', () async {
      final m = AviatorManager()
        ..register(Aviator(
            name: 'bad', navigateWhere: (_) async => throw StateError('no')));
      await expectLater(m.navigateAsync('bad', {}), throwsStateError);
    });

    test('closeAll closes every aviator and clears the registry', () async {
      final log = <String>[];
      final m = AviatorManager()
        ..register(_ClosingAviator('x', log))
        ..register(_ClosingAviator('y', log))
        ..register(_PlainAviator()); // default close() must not throw
      await m.closeAll();
      expect(log, unorderedEquals(['close:x', 'close:y']));
      expect(m.aviatorCount, 0);
      expect(m.hasAviator('x'), isFalse);
    });
  });

  group('DeepLinkAviator', () {
    const routes = {
      'shop/item': DeepLinkRoute(
        path: ['home', 'shop', 'item'],
        args: {'itemId': 42},
        requiredData: ['catalog', 'cart'],
      ),
      'home': DeepLinkRoute(path: ['home']),
    };

    test('walks every path step; only the last gets routeArgs', () async {
      final nav = <Map<String, dynamic>>[];
      final loaded = <String>[];
      final a = DeepLinkAviator(
        name: 'dl',
        navigate: nav.add,
        config: DeepLinkConfig(
          authRoute: 'login',
          routes: routes,
          checkAuth: () async => true,
          loadData: (k) async => loaded.add(k),
        ),
      );
      expect(a.name, 'dl');
      await a.navigateWhere({'deepLink': 'shop/item', 'extra': 1});

      expect(loaded, ['catalog', 'cart']);
      expect(nav.map((m) => m['route']), ['home', 'shop', 'item']);
      expect(nav.map((m) => m['isLastStep']), [false, false, true]);
      expect(nav.map((m) => m['routeArgs']), [
        null,
        null,
        {'itemId': 42}
      ]);
      expect(nav.every((m) => m['extra'] == 1 && m['deepLink'] == 'shop/item'),
          isTrue,
          reason: 'original args are forwarded on every step');
      await a.close();
    });

    test('unauthenticated → single redirect to authRoute, no data load',
        () async {
      final nav = <Map<String, dynamic>>[];
      final loaded = <String>[];
      final a = DeepLinkAviator(
        name: 'dl',
        navigate: nav.add,
        config: DeepLinkConfig(
          authRoute: 'login',
          routes: routes,
          checkAuth: () async => false,
          loadData: (k) async => loaded.add(k),
        ),
      );
      await a.navigateWhere({'deepLink': 'shop/item'});
      expect(nav, [
        {'deepLink': 'shop/item', 'route': 'login', 'isAuthRedirect': true}
      ]);
      expect(loaded, isEmpty);
    });

    test('no checkAuth / loadData: navigates directly', () async {
      final nav = <Map<String, dynamic>>[];
      final a = DeepLinkAviator(
        name: 'dl',
        navigate: nav.add,
        config: const DeepLinkConfig(authRoute: 'login', routes: routes),
      );
      await a.navigateWhere({'deepLink': 'home'});
      expect(nav, [
        {
          'deepLink': 'home',
          'route': 'home',
          'isLastStep': true,
          'routeArgs': <String, dynamic>{},
        }
      ]);
    });

    test('unknown deep link fails loudly with ArgumentError', () async {
      final nav = <Map<String, dynamic>>[];
      final a = DeepLinkAviator(
        name: 'dl',
        navigate: nav.add,
        config: const DeepLinkConfig(authRoute: 'login', routes: routes),
      );
      await expectLater(
          a.navigateWhere({'deepLink': 'nope'}), throwsA(isA<ArgumentError>()));
      expect(nav, isEmpty);
    });

    test('loadData failure aborts before any navigation', () async {
      final nav = <Map<String, dynamic>>[];
      final a = DeepLinkAviator(
        name: 'dl',
        navigate: nav.add,
        config: DeepLinkConfig(
          authRoute: 'login',
          routes: routes,
          loadData: (_) async => throw StateError('offline'),
        ),
      );
      await expectLater(
          a.navigateWhere({'deepLink': 'shop/item'}), throwsStateError);
      expect(nav, isEmpty);
    });

    test('driven through AviatorManager.navigateAsync', () async {
      final nav = <Map<String, dynamic>>[];
      final m = AviatorManager()
        ..register(DeepLinkAviator(
          name: 'dl',
          navigate: nav.add,
          config: const DeepLinkConfig(authRoute: 'login', routes: routes),
        ));
      await m.navigateAsync('dl', {'deepLink': 'shop/item'});
      expect(nav.last['route'], 'item');
    });
  });

  group('JuiceBloc wiring', () {
    test('emitUpdate/emitFailure with aviatorName navigate with args',
        () async {
      final got = <String>[];
      final bloc = _B([
        () => Aviator(name: 'detail', navigateWhere: (a) => got.add('d:$a')),
      ]);
      bloc.send(_Go('detail'));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      bloc.send(_Go('detail', fail: true));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      bloc.send(_Go(null)); // no aviator → no navigation
      bloc.send(_Go('unknown'));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(got, ['d:{id: 7}', 'd:{why: fail}']);
      await bloc.close();
    });

    test('bloc close closes its aviators', () async {
      final log = <String>[];
      final bloc = _B([() => _ClosingAviator('n', log)]);
      await bloc.close();
      expect(log, ['close:n']);
    });
  });

  group('navigate() failure handling (1.9.0)', () {
    late _AviatorErrorLogger logger;
    setUp(() {
      logger = _AviatorErrorLogger();
      JuiceLoggerConfig.configureLogger(logger);
    });
    tearDown(() => JuiceLoggerConfig.configureLogger(DefaultJuiceLogger()));

    test('an async navigation failure is logged, not an uncaught error',
        () async {
      final m = AviatorManager()
        ..register(DeepLinkAviator(
          name: 'dl',
          navigate: (_) {},
          config: const DeepLinkConfig(authRoute: 'l', routes: {}),
        ));
      m.navigate('dl', {'deepLink': 'nope'});
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(logger.aviatorErrors, ['dl']);
    });

    test('a synchronous navigation failure is logged too', () {
      final m = AviatorManager()
        ..register(Aviator(
          name: 'sync',
          navigateWhere: (_) => throw StateError('boom'),
        ));
      m.navigate('sync', null);
      expect(logger.aviatorErrors, ['sync']);
    });
  });
}

class _AviatorErrorLogger implements JuiceLogger {
  final aviatorErrors = <String>[];
  @override
  void log(String m,
      {Level level = Level.info, Map<String, dynamic>? context}) {}

  @override
  void logError(String m, Object e, StackTrace s,
      {Map<String, dynamic>? context}) {
    if (context?['type'] == 'aviator_error') {
      aviatorErrors.add(context!['aviator'] as String);
    }
  }
}
