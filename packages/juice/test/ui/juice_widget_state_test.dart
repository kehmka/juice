// JuiceWidgetState takes its groups/scope/resolver through the State's
// constructor, so the hosts below necessarily pass config in createState.
// ignore_for_file: no_logic_in_create_state

import 'package:flutter_test/flutter_test.dart';
import 'package:juice/juice.dart';

import 'juice_widget_test_support.dart';

/// Widget-level pins for JuiceWidgetState / 2 / 3: lease acquisition in
/// initState and release in dispose, group-filtered rebuilds, the
/// onInit / onStateChange / prepareForUpdate / onBuild / close hooks, scoped
/// resolution, and the legacy resolver path.

class _Log {
  final events = <String>[];
  final prepared = <StreamStatus>[];
  int builds = 0;
}

class _Opts {
  const _Opts({
    this.groups = rebuildAlways,
    this.resolver,
    this.accept,
    this.throwOnBuild = false,
  });
  final Set<String> groups;
  final BlocDependencyResolver? resolver;
  final bool Function(StreamStatus)? accept;
  final bool throwOnBuild;
}

// ---------------------------------------------------------------- single

class _H1 extends StatefulWidget {
  const _H1(this.log,
      {this.opts = const _Opts(), this.scope, this.bare = false});
  final _Log log;
  final _Opts opts;
  final Object? scope;
  final bool bare;

  @override
  State<_H1> createState() =>
      bare ? _Bare1State() : _S1(log, opts, scope: scope);
}

class _S1 extends JuiceWidgetState<BlocA, _H1> {
  _S1(this.log, this.opts, {super.scope})
      : super(groups: opts.groups, resolver: opts.resolver);
  final _Log log;
  final _Opts opts;

  @override
  void onInit() => log.events.add('init');

  @override
  bool onStateChange(StreamStatus status) => opts.accept?.call(status) ?? true;

  @override
  void prepareForUpdate(StreamStatus status) => log.prepared.add(status);

  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    log.builds++;
    if (opts.throwOnBuild) throw 'not an Exception';
    return Text('${kindOf(status)}:${bloc.state.v}');
  }

  @override
  Widget close(BuildContext context) => const Text('closed');
}

class _Bare1State extends JuiceWidgetState<BlocA, _H1> {}

// ---------------------------------------------------------------- double

class _H2 extends StatefulWidget {
  const _H2(this.log,
      {this.opts = const _Opts(), this.scope1, this.scope2, this.bare = false});
  final _Log log;
  final _Opts opts;
  final Object? scope1;
  final Object? scope2;
  final bool bare;

  @override
  State<_H2> createState() =>
      bare ? _Bare2State() : _S2(log, opts, scope1: scope1, scope2: scope2);
}

class _S2 extends JuiceWidgetState2<BlocA, BlocB, _H2> {
  _S2(this.log, this.opts, {super.scope1, super.scope2})
      : super(groups: opts.groups, resolver: opts.resolver);
  final _Log log;
  final _Opts opts;

  @override
  void onInit() => log.events.add('init');

  @override
  bool onStateChange(StreamStatus status) => opts.accept?.call(status) ?? true;

  @override
  void prepareForUpdate(StreamStatus status) => log.prepared.add(status);

  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    log.builds++;
    return Text('${kindOf(status)}:${bloc1.state.v}/${bloc2.state.v}');
  }

  @override
  Widget close(BuildContext context) => const Text('closed2');
}

class _Bare2State extends JuiceWidgetState2<BlocA, BlocB, _H2> {}

// ---------------------------------------------------------------- triple

class _H3 extends StatefulWidget {
  const _H3(this.log,
      {this.opts = const _Opts(),
      this.scope1,
      this.scope2,
      this.scope3,
      this.bare = false});
  final _Log log;
  final _Opts opts;
  final Object? scope1;
  final Object? scope2;
  final Object? scope3;
  final bool bare;

  @override
  State<_H3> createState() => bare
      ? _Bare3State()
      : _S3(log, opts, scope1: scope1, scope2: scope2, scope3: scope3);
}

class _S3 extends JuiceWidgetState3<BlocA, BlocB, BlocC, _H3> {
  _S3(this.log, this.opts, {super.scope1, super.scope2, super.scope3})
      : super(groups: opts.groups, resolver: opts.resolver);
  final _Log log;
  final _Opts opts;

  @override
  void onInit() => log.events.add('init');

  @override
  bool onStateChange(StreamStatus status) => opts.accept?.call(status) ?? true;

  @override
  void prepareForUpdate(StreamStatus status) => log.prepared.add(status);

  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    log.builds++;
    return Text(
        '${kindOf(status)}:${bloc1.state.v}/${bloc2.state.v}/${bloc3.state.v}');
  }

  @override
  Widget close(BuildContext context) => const Text('closed3');
}

class _Bare3State extends JuiceWidgetState3<BlocA, BlocB, BlocC, _H3> {}

Widget _app(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  setUp(quietReset);
  tearDown(restoreReset);

  group('JuiceWidgetState', () {
    testWidgets('initState leases, dispose releases; last lease closes bloc',
        (tester) async {
      BlocScope.register<BlocA>(() => BlocA(4),
          lifecycle: BlocLifecycle.leased);
      final log = _Log();
      await tester.pumpWidget(_app(_H1(log)));
      expect(find.text('U:4'), findsOneWidget);
      expect(log.events, ['init']);
      expect(BlocScope.diagnostics<BlocA>()!.leaseCount, 1);
      final bloc = BlocScope.peekExisting<BlocA>();

      await unmount(tester);
      expect(BlocScope.diagnostics<BlocA>()!.leaseCount, 0);
      expect(bloc.isClosed, isTrue);
    });

    testWidgets('groups filter rebuilds; rebuildAlways and optOut behave',
        (tester) async {
      BlocScope.register<BlocA>(() => BlocA());
      final narrow = _Log(), optOut = _Log();
      await tester.pumpWidget(_app(Column(children: [
        _H1(narrow, opts: const _Opts(groups: {'a'})),
        _H1(optOut, opts: const _Opts(groups: optOutOfRebuilds)),
      ])));
      final bloc = BlocScope.get<BlocA>();
      final n0 = narrow.builds, o0 = optOut.builds;

      await fire(tester, bloc, WEmit(1, groups: {'b'}));
      expect(narrow.builds, n0);

      await fire(tester, bloc, WEmit(2, groups: {'a'}));
      expect(narrow.builds, n0 + 1);

      await fire(tester, bloc, WEmit(3, groups: rebuildAlways));
      expect(narrow.builds, n0 + 2);
      expect(optOut.builds, o0, reason: 'optOut ignores even "*"');
      expect(find.text('U:3'), findsOneWidget);
      expect(find.text('U:0'), findsOneWidget);
    });

    testWidgets('onBuild sees every status kind', (tester) async {
      BlocScope.register<BlocA>(() => BlocA());
      await tester
          .pumpWidget(_app(_H1(_Log(), opts: const _Opts(groups: {'a'}))));
      final bloc = BlocScope.get<BlocA>();
      for (final (kind, label) in [
        (WKind.waiting, 'W'),
        (WKind.failure, 'F'),
        (WKind.cancel, 'C'),
        (WKind.update, 'U'),
      ]) {
        await fire(tester, bloc, WEmit(7, kind: kind));
        expect(find.text('$label:7'), findsOneWidget, reason: '$kind');
      }
    });

    testWidgets(
        'prepareForUpdate runs once per new status, not on parent rebuilds',
        (tester) async {
      BlocScope.register<BlocA>(() => BlocA());
      final log = _Log();
      Widget tree(String tag) => _app(Column(children: [
            Text(tag),
            _H1(log, opts: const _Opts(groups: {'a'})),
          ]));
      await tester.pumpWidget(tree('one'));
      expect(log.prepared, hasLength(1));

      await tester.pumpWidget(tree('two')); // parent rebuild only
      expect(log.prepared, hasLength(1));
      expect(log.builds, greaterThanOrEqualTo(2));

      final bloc = BlocScope.get<BlocA>();
      await fire(tester, bloc, WEmit(1));
      expect(log.prepared, hasLength(2));
      expect((log.prepared.last.state as WState).v, 1);
    });

    testWidgets('onStateChange false skips build and prepareForUpdate',
        (tester) async {
      BlocScope.register<BlocA>(() => BlocA());
      final log = _Log();
      await tester.pumpWidget(_app(_H1(log,
          opts:
              _Opts(groups: const {'a'}, accept: (s) => s is! FailureStatus))));
      final bloc = BlocScope.get<BlocA>();
      await fire(tester, bloc, WEmit(5, kind: WKind.failure));
      expect(find.text('U:0'), findsOneWidget);
      expect(log.prepared, hasLength(1));
      await fire(tester, bloc, WEmit(6));
      expect(find.text('U:6'), findsOneWidget);
    });

    testWidgets('a non-Exception throw from onBuild is wrapped and shown',
        (tester) async {
      BlocScope.register<BlocA>(() => BlocA());
      await tester
          .pumpWidget(_app(_H1(_Log(), opts: const _Opts(throwOnBuild: true))));
      final w = tester
          .widget<JuiceExceptionWidget>(find.byType(JuiceExceptionWidget));
      expect(w.exception.toString(), contains('not an Exception'));
    });

    testWidgets('bloc close renders close()', (tester) async {
      BlocScope.register<BlocA>(() => BlocA());
      await tester.pumpWidget(_app(_H1(_Log())));
      await closeBloc(tester, BlocScope.get<BlocA>());
      expect(find.text('closed'), findsOneWidget);
    });

    testWidgets('scope resolves the scoped instance', (tester) async {
      BlocScope.register<BlocA>(() => BlocA(1), scope: 'left');
      BlocScope.register<BlocA>(() => BlocA(2), scope: 'right');
      await tester.pumpWidget(_app(Column(children: [
        _H1(_Log(), opts: const _Opts(groups: {'a'}), scope: 'left'),
        _H1(_Log(), opts: const _Opts(groups: {'a'}), scope: 'right'),
      ])));
      await fire(tester, BlocScope.get<BlocA>(scope: 'left'), WEmit(10));
      expect(find.text('U:10'), findsOneWidget);
      expect(find.text('U:2'), findsOneWidget);
    });

    testWidgets('custom resolver: resolved once, no lease, not closed',
        (tester) async {
      final bloc = BlocA(3);
      final resolver = MapResolver({BlocA: bloc});
      await tester.pumpWidget(_app(
          _H1(_Log(), opts: _Opts(groups: const {'a'}, resolver: resolver))));
      expect(find.text('U:3'), findsOneWidget);
      await fire(tester, bloc, WEmit(9));
      expect(find.text('U:9'), findsOneWidget);
      expect(resolver.resolveCount, 1, reason: 'cached in initState');
      await unmount(tester);
      expect(bloc.isClosed, isFalse);
      await tester.runAsync(bloc.close);
    });

    testWidgets('base-class defaults render nothing', (tester) async {
      BlocScope.register<BlocA>(() => BlocA());
      await tester.pumpWidget(_app(_H1(_Log(), bare: true)));
      expect(find.byType(Text), findsNothing);
      await fire(tester, BlocScope.get<BlocA>(), WEmit(1, groups: {'*'}));
      await closeBloc(tester, BlocScope.get<BlocA>());
      expect(find.byType(Text), findsNothing);
    });
  });

  group('JuiceWidgetState2', () {
    testWidgets('rebuilds on either bloc and hooks run', (tester) async {
      BlocScope.register<BlocA>(() => BlocA(1));
      BlocScope.register<BlocB>(() => BlocB(2));
      final log = _Log();
      await tester.pumpWidget(_app(_H2(log, opts: const _Opts(groups: {'a'}))));
      expect(find.text('U:1/2'), findsOneWidget);
      expect(log.events, ['init']);

      await fire(
          tester, BlocScope.get<BlocB>(), WEmit(20, kind: WKind.waiting));
      expect(find.text('W:1/20'), findsOneWidget);
      await fire(tester, BlocScope.get<BlocA>(), WEmit(10));
      expect(find.text('U:10/20'), findsOneWidget);
      expect(log.prepared, hasLength(3));

      final b0 = log.builds;
      await fire(tester, BlocScope.get<BlocB>(), WEmit(0, groups: {'zz'}));
      expect(log.builds, b0);
    });

    testWidgets('onStateChange filters the merged stream', (tester) async {
      BlocScope.register<BlocA>(() => BlocA());
      BlocScope.register<BlocB>(() => BlocB());
      await tester.pumpWidget(
          _app(_H2(_Log(), opts: _Opts(accept: (s) => s is UpdatingStatus))));
      await fire(tester, BlocScope.get<BlocB>(),
          WEmit(4, kind: WKind.cancel, groups: {'*'}));
      expect(find.text('U:0/0'), findsOneWidget);
    });

    testWidgets('leases both, releases both; scoped', (tester) async {
      BlocScope.register<BlocA>(() => BlocA(1),
          scope: 's', lifecycle: BlocLifecycle.leased);
      BlocScope.register<BlocB>(() => BlocB(2),
          scope: 't', lifecycle: BlocLifecycle.leased);
      await tester.pumpWidget(_app(_H2(_Log(), scope1: 's', scope2: 't')));
      expect(find.text('U:1/2'), findsOneWidget);
      final a = BlocScope.peekExisting<BlocA>(scope: 's');
      final b = BlocScope.peekExisting<BlocB>(scope: 't');
      await unmount(tester);
      expect(a.isClosed && b.isClosed, isTrue);
    });

    testWidgets('close() after both blocs close', (tester) async {
      BlocScope.register<BlocA>(() => BlocA());
      BlocScope.register<BlocB>(() => BlocB());
      await tester.pumpWidget(_app(_H2(_Log())));
      await closeBloc(tester, BlocScope.get<BlocA>());
      await closeBloc(tester, BlocScope.get<BlocB>());
      expect(find.text('closed2'), findsOneWidget);
    });

    testWidgets('custom resolver path', (tester) async {
      final a = BlocA(1), b = BlocB(2);
      final r = MapResolver({BlocA: a, BlocB: b});
      await tester.pumpWidget(
          _app(_H2(_Log(), opts: _Opts(groups: const {'a'}, resolver: r))));
      await fire(tester, b, WEmit(3));
      expect(find.text('U:1/3'), findsOneWidget);
      expect(r.resolveCount, 2);
      await tester.runAsync(() async {
        await a.close();
        await b.close();
      });
    });

    testWidgets('base-class defaults', (tester) async {
      BlocScope.register<BlocA>(() => BlocA());
      BlocScope.register<BlocB>(() => BlocB());
      await tester.pumpWidget(_app(_H2(_Log(), bare: true)));
      await fire(tester, BlocScope.get<BlocA>(), WEmit(1, groups: {'*'}));
      await closeBloc(tester, BlocScope.get<BlocA>());
      await closeBloc(tester, BlocScope.get<BlocB>());
      expect(find.byType(Text), findsNothing);
    });
  });

  group('JuiceWidgetState3', () {
    testWidgets('rebuilds on any bloc and hooks run', (tester) async {
      BlocScope.register<BlocA>(() => BlocA(1));
      BlocScope.register<BlocB>(() => BlocB(2));
      BlocScope.register<BlocC>(() => BlocC(3));
      final log = _Log();
      await tester.pumpWidget(_app(_H3(log, opts: const _Opts(groups: {'a'}))));
      expect(find.text('U:1/2/3'), findsOneWidget);
      expect(log.events, ['init']);

      await fire(
          tester, BlocScope.get<BlocC>(), WEmit(30, kind: WKind.failure));
      expect(find.text('F:1/2/30'), findsOneWidget);
      await fire(tester, BlocScope.get<BlocB>(), WEmit(20));
      expect(find.text('U:1/20/30'), findsOneWidget);

      final b0 = log.builds;
      await fire(tester, BlocScope.get<BlocA>(), WEmit(0, groups: {'zz'}));
      expect(log.builds, b0);
    });

    testWidgets('onStateChange filters the merged stream', (tester) async {
      BlocScope.register<BlocA>(() => BlocA());
      BlocScope.register<BlocB>(() => BlocB());
      BlocScope.register<BlocC>(() => BlocC());
      await tester
          .pumpWidget(_app(_H3(_Log(), opts: _Opts(accept: (_) => false))));
      await fire(tester, BlocScope.get<BlocC>(), WEmit(4, groups: {'*'}));
      expect(find.text('U:0/0/0'), findsOneWidget);
    });

    testWidgets('leases all three, releases all; scoped', (tester) async {
      const leased = BlocLifecycle.leased;
      BlocScope.register<BlocA>(() => BlocA(1), scope: 1, lifecycle: leased);
      BlocScope.register<BlocB>(() => BlocB(2), scope: 2, lifecycle: leased);
      BlocScope.register<BlocC>(() => BlocC(3), scope: 3, lifecycle: leased);
      await tester
          .pumpWidget(_app(_H3(_Log(), scope1: 1, scope2: 2, scope3: 3)));
      expect(find.text('U:1/2/3'), findsOneWidget);
      final blocs = <JuiceBloc>[
        BlocScope.peekExisting<BlocA>(scope: 1),
        BlocScope.peekExisting<BlocB>(scope: 2),
        BlocScope.peekExisting<BlocC>(scope: 3),
      ];
      await unmount(tester);
      expect(blocs.every((b) => b.isClosed), isTrue);
    });

    testWidgets('close() after all blocs close', (tester) async {
      BlocScope.register<BlocA>(() => BlocA());
      BlocScope.register<BlocB>(() => BlocB());
      BlocScope.register<BlocC>(() => BlocC());
      await tester.pumpWidget(_app(_H3(_Log())));
      await closeBloc(tester, BlocScope.get<BlocA>());
      await closeBloc(tester, BlocScope.get<BlocB>());
      await closeBloc(tester, BlocScope.get<BlocC>());
      expect(find.text('closed3'), findsOneWidget);
    });

    testWidgets('custom resolver path', (tester) async {
      final a = BlocA(1), b = BlocB(2), c = BlocC(3);
      final r = MapResolver({BlocA: a, BlocB: b, BlocC: c});
      await tester.pumpWidget(
          _app(_H3(_Log(), opts: _Opts(groups: const {'a'}, resolver: r))));
      await fire(tester, c, WEmit(4));
      expect(find.text('U:1/2/4'), findsOneWidget);
      expect(r.resolveCount, 3);
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
      await tester.pumpWidget(_app(_H3(_Log(), bare: true)));
      await fire(tester, BlocScope.get<BlocA>(), WEmit(1, groups: {'*'}));
      await closeBloc(tester, BlocScope.get<BlocA>());
      await closeBloc(tester, BlocScope.get<BlocB>());
      await closeBloc(tester, BlocScope.get<BlocC>());
      expect(find.byType(Text), findsNothing);
    });
  });
}
