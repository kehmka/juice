import 'package:flutter_test/flutter_test.dart';
import 'package:juice/juice.dart';

import 'juice_widget_test_support.dart';

/// Widget-level pins for StatelessJuiceWidget / 2 / 3: group-filtered
/// rebuilds, per-status builds, hooks, the close() fallback, lease
/// acquisition/release through the private lease holders, scoped
/// resolution, and the legacy resolver path.

class _Log {
  final events = <String>[];
  int builds = 0;
}

class _W1 extends StatelessJuiceWidget<BlocA> {
  _W1(
    this.log, {
    super.groups,
    super.scope,
    super.resolver,
    this.accept,
    this.throwOnBuild = false,
  });

  final _Log log;
  final bool Function(StreamStatus)? accept;
  final bool throwOnBuild;

  @override
  void onInit() => log.events.add('init');

  @override
  bool onStateChange(StreamStatus status) => accept?.call(status) ?? true;

  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    log.builds++;
    if (throwOnBuild) throw StateError('bad build');
    return Text('${kindOf(status)}:${bloc.state.v}');
  }

  @override
  Widget close(BuildContext context) => const Text('closed');
}

/// Relies entirely on the base-class defaults (onBuild/close/hooks).
class _Bare extends StatelessJuiceWidget<BlocA> {
  _Bare();
}

class _W2 extends StatelessJuiceWidget2<BlocA, BlocB> {
  _W2(
    this.log, {
    super.groups,
    super.scope1,
    super.scope2,
    super.resolver,
    this.accept,
  });

  final _Log log;
  final bool Function(StreamStatus)? accept;

  @override
  void onInit() => log.events.add('init');

  @override
  bool onStateChange(StreamStatus status) => accept?.call(status) ?? true;

  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    log.builds++;
    return Text('${kindOf(status)}:${bloc1.state.v}/${bloc2.state.v}');
  }

  @override
  Widget close(BuildContext context) => const Text('closed2');
}

class _Bare2 extends StatelessJuiceWidget2<BlocA, BlocB> {
  _Bare2();
}

class _W3 extends StatelessJuiceWidget3<BlocA, BlocB, BlocC> {
  _W3(
    this.log, {
    super.groups,
    super.scope1,
    super.scope2,
    super.scope3,
    super.resolver,
    this.accept,
  });

  final _Log log;
  final bool Function(StreamStatus)? accept;

  @override
  void onInit() => log.events.add('init');

  @override
  bool onStateChange(StreamStatus status) => accept?.call(status) ?? true;

  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    log.builds++;
    return Text(
        '${kindOf(status)}:${bloc1.state.v}/${bloc2.state.v}/${bloc3.state.v}');
  }

  @override
  Widget close(BuildContext context) => const Text('closed3');
}

class _Bare3 extends StatelessJuiceWidget3<BlocA, BlocB, BlocC> {
  _Bare3();
}

Widget _app(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  setUp(quietReset);
  tearDown(restoreReset);

  group('StatelessJuiceWidget', () {
    testWidgets('renders current state and calls onInit once', (tester) async {
      BlocScope.register<BlocA>(() => BlocA(5));
      final log = _Log();
      await tester.pumpWidget(_app(_W1(log, groups: const {'a'})));
      expect(find.text('U:5'), findsOneWidget);
      expect(log.events, ['init']);

      // A parent rebuild does not re-run onInit.
      await tester.pumpWidget(_app(_W1(log, groups: const {'a'})));
      expect(log.events, ['init']);
    });

    testWidgets('rebuilds only when emission groups intersect its groups',
        (tester) async {
      BlocScope.register<BlocA>(() => BlocA());
      final log = _Log();
      await tester.pumpWidget(_app(_W1(log, groups: const {'a', 'x'})));
      final bloc = BlocScope.get<BlocA>();
      final base = log.builds;

      await fire(tester, bloc, WEmit(1, groups: {'b'}));
      expect(log.builds, base, reason: '{b} ∩ {a,x} is empty');
      expect(find.text('U:0'), findsOneWidget);

      await fire(tester, bloc, WEmit(2, groups: {'x', 'zzz'}));
      expect(log.builds, base + 1);
      expect(find.text('U:2'), findsOneWidget);
    });

    testWidgets('rebuildAlways emission reaches a narrowly-grouped widget',
        (tester) async {
      BlocScope.register<BlocA>(() => BlocA());
      final log = _Log();
      await tester.pumpWidget(_app(_W1(log, groups: const {'narrow'})));
      await fire(
          tester, BlocScope.get<BlocA>(), WEmit(9, groups: rebuildAlways));
      expect(find.text('U:9'), findsOneWidget);
    });

    testWidgets('optOutOfRebuilds never rebuilds, even for rebuildAlways',
        (tester) async {
      BlocScope.register<BlocA>(() => BlocA());
      final log = _Log();
      await tester.pumpWidget(_app(_W1(log, groups: optOutOfRebuilds)));
      final base = log.builds;
      await fire(
          tester, BlocScope.get<BlocA>(), WEmit(3, groups: rebuildAlways));
      expect(log.builds, base);
      expect(find.text('U:0'), findsOneWidget);
    });

    testWidgets('default groups rebuild on a rebuildAlways emission',
        (tester) async {
      BlocScope.register<BlocA>(() => BlocA());
      final log = _Log();
      await tester.pumpWidget(_app(_W1(log)));
      await fire(tester, BlocScope.get<BlocA>(), WEmit(4, groups: {'*'}));
      expect(find.text('U:4'), findsOneWidget);
    });

    testWidgets('onBuild receives each status kind', (tester) async {
      BlocScope.register<BlocA>(() => BlocA());
      await tester.pumpWidget(_app(_W1(_Log(), groups: const {'a'})));
      final bloc = BlocScope.get<BlocA>();

      await fire(tester, bloc, WEmit(1, kind: WKind.waiting));
      expect(find.text('W:1'), findsOneWidget);
      await fire(tester, bloc, WEmit(2, kind: WKind.failure));
      expect(find.text('F:2'), findsOneWidget);
      await fire(tester, bloc, WEmit(3, kind: WKind.cancel));
      expect(find.text('C:3'), findsOneWidget);
      await fire(tester, bloc, WEmit(4));
      expect(find.text('U:4'), findsOneWidget);
    });

    testWidgets('onStateChange returning false suppresses the rebuild',
        (tester) async {
      BlocScope.register<BlocA>(() => BlocA());
      final log = _Log();
      await tester.pumpWidget(_app(
          _W1(log, groups: const {'a'}, accept: (s) => s is! WaitingStatus)));
      final bloc = BlocScope.get<BlocA>();

      await fire(tester, bloc, WEmit(1, kind: WKind.waiting));
      expect(find.text('U:0'), findsOneWidget, reason: 'waiting filtered');
      await fire(tester, bloc, WEmit(2));
      expect(find.text('U:2'), findsOneWidget);
    });

    testWidgets('a throwing onBuild renders JuiceExceptionWidget',
        (tester) async {
      BlocScope.register<BlocA>(() => BlocA());
      await tester.pumpWidget(_app(_W1(_Log(), throwOnBuild: true)));
      expect(find.byType(JuiceExceptionWidget), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('bloc close switches to the close() builder', (tester) async {
      BlocScope.register<BlocA>(() => BlocA());
      await tester.pumpWidget(_app(_W1(_Log())));
      expect(find.text('U:0'), findsOneWidget);
      await closeBloc(tester, BlocScope.get<BlocA>());
      expect(find.text('closed'), findsOneWidget);
    });

    testWidgets('base-class defaults render an empty box, open and closed',
        (tester) async {
      BlocScope.register<BlocA>(() => BlocA());
      await tester.pumpWidget(_app(_Bare()));
      final bloc = BlocScope.get<BlocA>();
      await fire(tester, bloc, WEmit(1, groups: rebuildAlways));
      expect(find.byType(SizedBox), findsWidgets);
      expect(find.byType(Text), findsNothing);
      await closeBloc(tester, bloc);
      expect(find.byType(Text), findsNothing);
    });

    testWidgets(
        'leased bloc: each mounted widget holds a lease; the last unmount '
        'closes the bloc', (tester) async {
      BlocScope.register<BlocA>(() => BlocA(), lifecycle: BlocLifecycle.leased);
      expect(BlocScope.diagnostics<BlocA>()!.isActive, isFalse);

      final keepSecond = ValueNotifier(true);
      await tester.pumpWidget(_app(ValueListenableBuilder<bool>(
        valueListenable: keepSecond,
        builder: (_, keep, __) =>
            Column(children: [_W1(_Log()), if (keep) _W1(_Log())]),
      )));
      final bloc = BlocScope.peekExisting<BlocA>();
      expect(BlocScope.diagnostics<BlocA>()!.leaseCount, 2);

      keepSecond.value = false;
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      expect(BlocScope.diagnostics<BlocA>()!.leaseCount, 1);
      expect(bloc.isClosed, isFalse);

      await unmount(tester);
      expect(BlocScope.diagnostics<BlocA>()!.leaseCount, 0);
      expect(bloc.isClosed, isTrue);
      expect(BlocScope.diagnostics<BlocA>()!.isActive, isFalse);
      keepSecond.dispose();
    });

    testWidgets('permanent bloc survives widget unmount', (tester) async {
      BlocScope.register<BlocA>(() => BlocA());
      await tester.pumpWidget(_app(_W1(_Log())));
      final bloc = BlocScope.peekExisting<BlocA>();
      await unmount(tester);
      expect(BlocScope.diagnostics<BlocA>()!.leaseCount, 0);
      expect(bloc.isClosed, isFalse);
    });

    testWidgets('scope selects the instance and only that one drives rebuilds',
        (tester) async {
      BlocScope.register<BlocA>(() => BlocA(1), scope: 's1');
      BlocScope.register<BlocA>(() => BlocA(2), scope: 's2');
      await tester.pumpWidget(_app(Column(children: [
        _W1(_Log(), scope: 's1', groups: const {'a'}),
        _W1(_Log(), scope: 's2', groups: const {'a'}),
      ])));
      expect(find.text('U:1'), findsOneWidget);
      expect(find.text('U:2'), findsOneWidget);

      await fire(tester, BlocScope.get<BlocA>(scope: 's2'), WEmit(20));
      expect(find.text('U:1'), findsOneWidget);
      expect(find.text('U:20'), findsOneWidget);
    });

    testWidgets('legacy resolver path: no BlocScope registration or lease',
        (tester) async {
      final bloc = BlocA(7);
      final resolver = MapResolver({BlocA: bloc});
      await tester.pumpWidget(
          _app(_W1(_Log(), resolver: resolver, groups: const {'a'})));
      expect(find.text('U:7'), findsOneWidget);
      expect(BlocScope.isRegistered<BlocA>(), isFalse);

      await fire(tester, bloc, WEmit(8));
      expect(find.text('U:8'), findsOneWidget);

      await unmount(tester);
      expect(bloc.isClosed, isFalse, reason: 'resolver owns lifecycle');
      await tester.runAsync(bloc.close);
    });
  });

  group('StatelessJuiceWidget2', () {
    testWidgets('rebuilds on either bloc, filtered by groups', (tester) async {
      BlocScope.register<BlocA>(() => BlocA(1));
      BlocScope.register<BlocB>(() => BlocB(2));
      final log = _Log();
      await tester.pumpWidget(_app(_W2(log, groups: const {'a'})));
      expect(find.text('U:1/2'), findsOneWidget);
      expect(log.events, ['init']);

      await fire(tester, BlocScope.get<BlocB>(), WEmit(20));
      expect(find.text('U:1/20'), findsOneWidget);
      await fire(
          tester, BlocScope.get<BlocA>(), WEmit(10, kind: WKind.failure));
      expect(find.text('F:10/20'), findsOneWidget);

      final base = log.builds;
      await fire(tester, BlocScope.get<BlocB>(), WEmit(99, groups: {'other'}));
      expect(log.builds, base);
    });

    testWidgets('onStateChange filters merged emissions', (tester) async {
      BlocScope.register<BlocA>(() => BlocA());
      BlocScope.register<BlocB>(() => BlocB());
      await tester
          .pumpWidget(_app(_W2(_Log(), accept: (s) => s is! CancelingStatus)));
      await fire(tester, BlocScope.get<BlocB>(),
          WEmit(5, kind: WKind.cancel, groups: rebuildAlways));
      expect(find.text('U:0/0'), findsOneWidget);
    });

    testWidgets('leases both blocs and releases both on unmount',
        (tester) async {
      BlocScope.register<BlocA>(() => BlocA(), lifecycle: BlocLifecycle.leased);
      BlocScope.register<BlocB>(() => BlocB(), lifecycle: BlocLifecycle.leased);
      await tester.pumpWidget(_app(_W2(_Log())));
      final a = BlocScope.peekExisting<BlocA>();
      final b = BlocScope.peekExisting<BlocB>();
      expect(BlocScope.diagnostics<BlocA>()!.leaseCount, 1);
      expect(BlocScope.diagnostics<BlocB>()!.leaseCount, 1);
      await unmount(tester);
      expect(a.isClosed, isTrue);
      expect(b.isClosed, isTrue);
    });

    testWidgets('scope1/scope2 pick scoped instances', (tester) async {
      BlocScope.register<BlocA>(() => BlocA(3), scope: 'x');
      BlocScope.register<BlocB>(() => BlocB(4), scope: 'y');
      await tester.pumpWidget(_app(_W2(_Log(), scope1: 'x', scope2: 'y')));
      expect(find.text('U:3/4'), findsOneWidget);
    });

    testWidgets('close() shows once both blocs have closed', (tester) async {
      BlocScope.register<BlocA>(() => BlocA());
      BlocScope.register<BlocB>(() => BlocB());
      await tester.pumpWidget(_app(_W2(_Log())));
      await closeBloc(tester, BlocScope.get<BlocA>());
      await closeBloc(tester, BlocScope.get<BlocB>());
      expect(find.text('closed2'), findsOneWidget);
    });

    testWidgets('legacy resolver path', (tester) async {
      final a = BlocA(1), b = BlocB(2);
      await tester.pumpWidget(_app(_W2(_Log(),
          groups: const {'a'}, resolver: MapResolver({BlocA: a, BlocB: b}))));
      expect(find.text('U:1/2'), findsOneWidget);
      await fire(tester, b, WEmit(5));
      expect(find.text('U:1/5'), findsOneWidget);
      await tester.runAsync(() async {
        await a.close();
        await b.close();
      });
    });

    testWidgets('base-class defaults', (tester) async {
      BlocScope.register<BlocA>(() => BlocA());
      BlocScope.register<BlocB>(() => BlocB());
      await tester.pumpWidget(_app(_Bare2()));
      await fire(tester, BlocScope.get<BlocB>(), WEmit(1, groups: {'*'}));
      expect(find.byType(Text), findsNothing);
      await closeBloc(tester, BlocScope.get<BlocA>());
      await closeBloc(tester, BlocScope.get<BlocB>());
      expect(find.byType(Text), findsNothing);
    });
  });

  group('StatelessJuiceWidget3', () {
    testWidgets('rebuilds on any of the three blocs', (tester) async {
      BlocScope.register<BlocA>(() => BlocA(1));
      BlocScope.register<BlocB>(() => BlocB(2));
      BlocScope.register<BlocC>(() => BlocC(3));
      final log = _Log();
      await tester.pumpWidget(_app(_W3(log, groups: const {'a'})));
      expect(find.text('U:1/2/3'), findsOneWidget);
      expect(log.events, ['init']);

      await fire(
          tester, BlocScope.get<BlocC>(), WEmit(30, kind: WKind.waiting));
      expect(find.text('W:1/2/30'), findsOneWidget);
      await fire(tester, BlocScope.get<BlocB>(), WEmit(20));
      expect(find.text('U:1/20/30'), findsOneWidget);

      final base = log.builds;
      await fire(tester, BlocScope.get<BlocA>(), WEmit(99, groups: {'nope'}));
      expect(log.builds, base);
    });

    testWidgets('onStateChange filters merged emissions', (tester) async {
      BlocScope.register<BlocA>(() => BlocA());
      BlocScope.register<BlocB>(() => BlocB());
      BlocScope.register<BlocC>(() => BlocC());
      await tester.pumpWidget(_app(_W3(_Log(), accept: (_) => false)));
      await fire(tester, BlocScope.get<BlocC>(), WEmit(5, groups: {'*'}));
      expect(find.text('U:0/0/0'), findsOneWidget);
    });

    testWidgets('leases all three and releases all on unmount', (tester) async {
      BlocScope.register<BlocA>(() => BlocA(), lifecycle: BlocLifecycle.leased);
      BlocScope.register<BlocB>(() => BlocB(), lifecycle: BlocLifecycle.leased);
      BlocScope.register<BlocC>(() => BlocC(), lifecycle: BlocLifecycle.leased);
      await tester.pumpWidget(_app(_W3(_Log())));
      final blocs = [
        BlocScope.peekExisting<BlocA>(),
        BlocScope.peekExisting<BlocB>(),
        BlocScope.peekExisting<BlocC>(),
      ];
      expect(BlocScope.diagnostics<BlocC>()!.leaseCount, 1);
      await unmount(tester);
      expect(blocs.every((b) => b.isClosed), isTrue);
    });

    testWidgets('scoped instances and close()', (tester) async {
      BlocScope.register<BlocA>(() => BlocA(1), scope: 1);
      BlocScope.register<BlocB>(() => BlocB(2), scope: 2);
      BlocScope.register<BlocC>(() => BlocC(3), scope: 3);
      await tester
          .pumpWidget(_app(_W3(_Log(), scope1: 1, scope2: 2, scope3: 3)));
      expect(find.text('U:1/2/3'), findsOneWidget);
      await closeBloc(tester, BlocScope.get<BlocA>(scope: 1));
      await closeBloc(tester, BlocScope.get<BlocB>(scope: 2));
      await closeBloc(tester, BlocScope.get<BlocC>(scope: 3));
      expect(find.text('closed3'), findsOneWidget);
    });

    testWidgets('legacy resolver path', (tester) async {
      final a = BlocA(1), b = BlocB(2), c = BlocC(3);
      await tester.pumpWidget(_app(_W3(_Log(),
          groups: const {'a'},
          resolver: MapResolver({BlocA: a, BlocB: b, BlocC: c}))));
      expect(find.text('U:1/2/3'), findsOneWidget);
      await fire(tester, c, WEmit(6));
      expect(find.text('U:1/2/6'), findsOneWidget);
      await tester.runAsync(() async {
        await a.close();
        await b.close();
        await c.close();
      });
    });

    testWidgets('base-class defaults', (tester) async {
      BlocScope.register<BlocA>(() => BlocA());
      BlocScope.register<BlocB>(() => BlocB());
      BlocScope.register<BlocC>(() => BlocC());
      await tester.pumpWidget(_app(_Bare3()));
      await fire(tester, BlocScope.get<BlocC>(), WEmit(1, groups: {'*'}));
      expect(find.byType(Text), findsNothing);
      await closeBloc(tester, BlocScope.get<BlocA>());
      await closeBloc(tester, BlocScope.get<BlocB>());
      await closeBloc(tester, BlocScope.get<BlocC>());
      expect(find.byType(Text), findsNothing);
    });
  });

  group('1.9.0: a widget rebuilt with a different scope follows it', () {
    testWidgets('switches its lease and its stream to the new scope',
        (tester) async {
      BlocScope.register<BlocA>(() => BlocA(1), scope: 's1');
      BlocScope.register<BlocA>(() => BlocA(2),
          scope: 's2', lifecycle: BlocLifecycle.leased);
      await tester
          .pumpWidget(_app(_W1(_Log(), scope: 's1', groups: const {'a'})));
      expect(find.text('U:1'), findsOneWidget);

      await tester
          .pumpWidget(_app(_W1(_Log(), scope: 's2', groups: const {'a'})));
      expect(find.text('U:2'), findsOneWidget,
          reason: 'a leased s2 was never leased, so the getter threw');
      expect(BlocScope.diagnostics<BlocA>(scope: 's2')!.leaseCount, 1);
      expect(BlocScope.diagnostics<BlocA>(scope: 's1')!.leaseCount, 0,
          reason: 'the old lease is released');

      await fire(tester, BlocScope.peekExisting<BlocA>(scope: 's2'), WEmit(20));
      expect(find.text('U:20'), findsOneWidget,
          reason: 'was still listening to s1');
    });
  });
}
