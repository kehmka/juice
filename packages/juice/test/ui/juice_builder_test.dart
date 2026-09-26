import 'package:flutter_test/flutter_test.dart';
import 'package:juice/juice.dart';

/// Pins for `JuiceBuilder`, `JuiceBuilder2` and `JuiceMultiBuilder`: group
/// filtering (via `denyRebuild`), `buildWhen`, resolver-vs-lease resolution,
/// lease release on dispose, lifecycle callbacks, and builder exceptions.

class _S extends BlocState {
  final int count;
  const _S({this.count = 0});
}

/// Increments `count` and emits with [groups] (null → framework default,
/// which is `rebuildAlways`).
class _Inc extends EventBase {
  final Set<String>? groups;
  _Inc([this.groups]);
}

class _IncUC<B extends JuiceBloc<_S>> extends BlocUseCase<B, _Inc> {
  @override
  Future<void> execute(_Inc e) async => emitUpdate(
      newState: _S(count: bloc.state.count + 1), groupsToRebuild: e.groups);
}

class _A extends JuiceBloc<_S> {
  _A()
      : super(const _S(), [
          () => UseCaseBuilder(
              typeOfEvent: _Inc,
              useCaseGenerator: () => _IncUC<_A>(),
              concurrency: EventConcurrency.sequential),
        ]);
}

class _B extends JuiceBloc<_S> {
  _B()
      : super(const _S(count: 100), [
          () => UseCaseBuilder(
              typeOfEvent: _Inc,
              useCaseGenerator: () => _IncUC<_B>(),
              concurrency: EventConcurrency.sequential),
        ]);
}

/// Resolver that hands out fixed instances and records what was asked for.
class _FixedResolver implements BlocDependencyResolver {
  _FixedResolver(this.blocs);
  final Map<Type, JuiceBloc> blocs;
  final resolved = <Type>[];

  @override
  T resolve<T extends JuiceBloc<BlocState>>({Map<String, dynamic>? args}) {
    resolved.add(T);
    return blocs[T] as T;
  }

  @override
  BlocLease<T> lease<T extends JuiceBloc<BlocState>>({Object? scope}) =>
      throw UnimplementedError();

  @override
  Future<void> disposeAll() async {}
}

Future<void> _send(WidgetTester tester, JuiceBloc bloc, _Inc e) async {
  await tester.runAsync(() async {
    bloc.send(e);
    await Future<void>.delayed(const Duration(milliseconds: 10));
  });
  await tester.pump();
}

void main() {
  setUp(BlocScope.reset);
  tearDown(BlocScope.reset);

  group('JuiceBuilder', () {
    testWidgets('builds initial state from a BlocScope lease', (tester) async {
      BlocScope.register<_A>(() => _A());
      await tester.pumpWidget(MaterialApp(
        home: JuiceBuilder<_A>(
          builder: (_, bloc, status) => Text('c=${bloc.state.count}'),
        ),
      ));
      expect(find.text('c=0'), findsOneWidget);
    });

    testWidgets('rebuilds only when emitted groups intersect its groups',
        (tester) async {
      BlocScope.register<_A>(() => _A());
      final bloc = BlocScope.get<_A>();
      var builds = 0;
      await tester.pumpWidget(MaterialApp(
        home: JuiceBuilder<_A>(
          groups: const {'a'},
          builder: (_, b, __) {
            builds++;
            return Text('c=${b.state.count}');
          },
        ),
      ));
      expect(builds, 1);

      await _send(tester, bloc, _Inc({'other'}));
      expect(builds, 1, reason: 'non-intersecting group must not rebuild');
      expect(bloc.state.count, 1);

      await _send(tester, bloc, _Inc({'a', 'x'}));
      expect(builds, 2);
      expect(find.text('c=2'), findsOneWidget);

      await _send(tester, bloc, _Inc(rebuildAlways));
      expect(builds, 3, reason: 'rebuildAlways reaches every group');
    });

    testWidgets(
        'default groups {*} rebuild on broadcast emissions but not '
        'on targeted ones', (tester) async {
      BlocScope.register<_A>(() => _A());
      final bloc = BlocScope.get<_A>();
      var builds = 0;
      await tester.pumpWidget(MaterialApp(
        home: JuiceBuilder<_A>(builder: (_, b, __) {
          builds++;
          return Text('c=${b.state.count}');
        }),
      ));
      await _send(tester, bloc, _Inc()); // null groups → rebuildAlways
      expect(builds, 2);
      await _send(tester, bloc, _Inc({'targeted'}));
      expect(builds, 2);
    });

    testWidgets('optOutOfRebuilds never rebuilds', (tester) async {
      BlocScope.register<_A>(() => _A());
      final bloc = BlocScope.get<_A>();
      var builds = 0;
      await tester.pumpWidget(MaterialApp(
        home: JuiceBuilder<_A>(
          groups: optOutOfRebuilds,
          builder: (_, b, __) {
            builds++;
            return const SizedBox();
          },
        ),
      ));
      await _send(tester, bloc, _Inc(rebuildAlways));
      expect(builds, 1);
    });

    testWidgets('buildWhen filters after group matching and sees the status',
        (tester) async {
      BlocScope.register<_A>(() => _A());
      final bloc = BlocScope.get<_A>();
      final seen = <int>[];
      var builds = 0;
      await tester.pumpWidget(MaterialApp(
        home: JuiceBuilder<_A>(
          groups: const {'a'},
          buildWhen: (status) {
            seen.add((status.state as _S).count);
            return (status.state as _S).count.isEven;
          },
          builder: (_, b, status) {
            builds++;
            return Text('c=${(status.state as _S).count}');
          },
        ),
      ));

      await _send(tester, bloc, _Inc({'zzz'}));
      expect(seen, isEmpty, reason: 'buildWhen not consulted on group miss');

      await _send(tester, bloc, _Inc({'a'})); // count 2 → even
      expect(builds, 2);
      expect(find.text('c=2'), findsOneWidget);

      await _send(tester, bloc, _Inc({'a'})); // count 3 → odd, skipped
      expect(builds, 2);
      expect(find.text('c=2'), findsOneWidget);
      expect(seen, [2, 3]);
    });

    testWidgets('resolver path uses the resolver, takes no lease',
        (tester) async {
      final bloc = _A();
      final resolver = _FixedResolver({_A: bloc});
      await tester.pumpWidget(MaterialApp(
        home: JuiceBuilder<_A>(
          resolver: resolver,
          groups: const {'a'},
          builder: (_, b, __) => Text('same=${identical(b, bloc)}'),
        ),
      ));
      expect(resolver.resolved, [_A]);
      expect(find.text('same=true'), findsOneWidget);
      expect(BlocScope.isRegistered<_A>(), isFalse);

      await _send(tester, bloc, _Inc({'a'}));
      await tester.pumpWidget(const SizedBox());
      expect(bloc.isClosed, isFalse,
          reason: 'resolver-provided bloc is not owned by the widget');
      await tester.runAsync(bloc.close);
    });

    testWidgets('onInit/onDispose fire once; leased bloc closes on dispose',
        (tester) async {
      BlocScope.register<_A>(() => _A(), lifecycle: BlocLifecycle.leased);
      final calls = <String>[];
      _A? seen;
      await tester.pumpWidget(MaterialApp(
        home: JuiceBuilder<_A>(
          onInit: () => calls.add('init'),
          onDispose: () => calls.add('dispose'),
          builder: (_, b, __) {
            seen = b;
            return const SizedBox();
          },
        ),
      ));
      expect(calls, ['init']);
      expect(seen!.isClosed, isFalse);

      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
      expect(calls, ['init', 'dispose']);
      expect(seen!.isClosed, isTrue,
          reason: 'last lease released → leased bloc auto-closes');
    });

    testWidgets('leased bloc stays open while another builder holds a lease',
        (tester) async {
      BlocScope.register<_A>(() => _A(), lifecycle: BlocLifecycle.leased);
      final show = ValueNotifier(true);
      _A? seen;
      await tester.pumpWidget(MaterialApp(
        home: ValueListenableBuilder<bool>(
          valueListenable: show,
          builder: (_, v, __) => Column(children: [
            if (v) JuiceBuilder<_A>(builder: (_, b, __) => const Text('first')),
            JuiceBuilder<_A>(builder: (_, b, __) {
              seen = b;
              return const Text('second');
            }),
          ]),
        ),
      ));
      show.value = false;
      await tester.pump();
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
      expect(find.text('first'), findsNothing);
      expect(seen!.isClosed, isFalse);

      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
      expect(seen!.isClosed, isTrue);
    });

    testWidgets('no setState after dispose when bloc emits later',
        (tester) async {
      BlocScope.register<_A>(() => _A());
      final bloc = BlocScope.get<_A>();
      var builds = 0;
      await tester.pumpWidget(MaterialApp(
        home: JuiceBuilder<_A>(builder: (_, b, __) {
          builds++;
          return const SizedBox();
        }),
      ));
      await tester.pumpWidget(const SizedBox());
      await _send(tester, bloc, _Inc(rebuildAlways));
      expect(builds, 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('builder Exception is rendered as JuiceExceptionWidget as-is',
        (tester) async {
      BlocScope.register<_A>(() => _A());
      const boom = FormatException('bad format');
      await tester.pumpWidget(MaterialApp(
        home: JuiceBuilder<_A>(builder: (_, __, ___) => throw boom),
      ));
      final w = tester
          .widget<JuiceExceptionWidget>(find.byType(JuiceExceptionWidget));
      expect(identical(w.exception, boom), isTrue);
      expect(find.textContaining('bad format'), findsWidgets);
    });

    testWidgets('builder non-Exception Error is wrapped into an Exception',
        (tester) async {
      BlocScope.register<_A>(() => _A());
      await tester.pumpWidget(MaterialApp(
        home: JuiceBuilder<_A>(builder: (_, __, ___) => throw StateError('x')),
      ));
      final w = tester
          .widget<JuiceExceptionWidget>(find.byType(JuiceExceptionWidget));
      expect(w.exception.toString(), contains('Bad state: x'));
    });

    testWidgets('unregistered bloc fails loudly in initState', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: JuiceBuilder<_A>(builder: (_, __, ___) => const SizedBox()),
      ));
      expect(tester.takeException(), isA<StateError>());
    });
  });

  group('JuiceBuilder2', () {
    testWidgets('merges both blocs, filtered by groups', (tester) async {
      BlocScope.register<_A>(() => _A());
      BlocScope.register<_B>(() => _B());
      final a = BlocScope.get<_A>();
      final b = BlocScope.get<_B>();
      var builds = 0;
      await tester.pumpWidget(MaterialApp(
        home: JuiceBuilder2<_A, _B>(
          groups: const {'g'},
          builder: (_, a, b, __) {
            builds++;
            return Text('${a.state.count}/${b.state.count}');
          },
        ),
      ));
      expect(find.text('0/100'), findsOneWidget);

      await _send(tester, a, _Inc({'g'}));
      expect(find.text('1/100'), findsOneWidget);
      await _send(tester, b, _Inc({'g'}));
      expect(find.text('1/101'), findsOneWidget);
      expect(builds, 3);

      await _send(tester, b, _Inc({'nope'}));
      expect(builds, 3);
    });

    testWidgets('buildWhen gates merged emissions', (tester) async {
      BlocScope.register<_A>(() => _A());
      BlocScope.register<_B>(() => _B());
      final a = BlocScope.get<_A>();
      final b = BlocScope.get<_B>();
      var builds = 0;
      await tester.pumpWidget(MaterialApp(
        home: JuiceBuilder2<_A, _B>(
          groups: const {'g'},
          buildWhen: (s) => s.state is _S && (s.state as _S).count >= 100,
          builder: (_, __, ___, ____) {
            builds++;
            return const SizedBox();
          },
        ),
      ));
      await _send(tester, a, _Inc({'g'}));
      expect(builds, 1);
      await _send(tester, b, _Inc({'g'}));
      expect(builds, 2);
    });

    testWidgets('resolver path resolves both types', (tester) async {
      final a = _A();
      final b = _B();
      final resolver = _FixedResolver({_A: a, _B: b});
      await tester.pumpWidget(MaterialApp(
        home: JuiceBuilder2<_A, _B>(
          resolver: resolver,
          builder: (_, x, y, __) =>
              Text('${identical(x, a)}${identical(y, b)}'),
        ),
      ));
      expect(resolver.resolved, [_A, _B]);
      expect(find.text('truetrue'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      expect(a.isClosed || b.isClosed, isFalse);
      await tester.runAsync(() async {
        await a.close();
        await b.close();
      });
    });

    testWidgets('callbacks fire and both leases release on dispose',
        (tester) async {
      BlocScope.register<_A>(() => _A(), lifecycle: BlocLifecycle.leased);
      BlocScope.register<_B>(() => _B(), lifecycle: BlocLifecycle.leased);
      final calls = <String>[];
      late _A a;
      late _B b;
      await tester.pumpWidget(MaterialApp(
        home: JuiceBuilder2<_A, _B>(
          onInit: () => calls.add('init'),
          onDispose: () => calls.add('dispose'),
          builder: (_, x, y, __) {
            a = x;
            b = y;
            return const SizedBox();
          },
        ),
      ));
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
      expect(calls, ['init', 'dispose']);
      expect(a.isClosed, isTrue);
      expect(b.isClosed, isTrue);
    });

    testWidgets('builder errors render JuiceExceptionWidget', (tester) async {
      BlocScope.register<_A>(() => _A());
      BlocScope.register<_B>(() => _B());
      await tester.pumpWidget(MaterialApp(
        home: JuiceBuilder2<_A, _B>(
            builder: (_, __, ___, ____) => throw ArgumentError('two')),
      ));
      final w = tester
          .widget<JuiceExceptionWidget>(find.byType(JuiceExceptionWidget));
      expect(w.exception.toString(), contains('two'));
    });
  });

  group('JuiceMultiBuilder', () {
    testWidgets('explicit blocs: merges all streams, filtered by groups',
        (tester) async {
      final a = _A();
      final b = _B();
      var builds = 0;
      await tester.pumpWidget(MaterialApp(
        home: JuiceMultiBuilder(
          blocs: [a, b],
          groups: const {'m'},
          builder: (_, blocs, __) {
            builds++;
            return Text(
                blocs.map((x) => (x.state as _S).count.toString()).join(','));
          },
        ),
      ));
      expect(find.text('0,100'), findsOneWidget);

      await _send(tester, b, _Inc({'m'}));
      expect(find.text('0,101'), findsOneWidget);
      await _send(tester, a, _Inc({'other'}));
      expect(builds, 2);

      await tester.pumpWidget(const SizedBox());
      expect(a.isClosed || b.isClosed, isFalse,
          reason: 'explicit blocs are not owned by the widget');
      await tester.runAsync(() async {
        await a.close();
        await b.close();
      });
    });

    testWidgets('buildWhen and callbacks', (tester) async {
      final a = _A();
      final calls = <String>[];
      var builds = 0;
      await tester.pumpWidget(MaterialApp(
        home: JuiceMultiBuilder(
          blocs: [a],
          onInit: () => calls.add('init'),
          onDispose: () => calls.add('dispose'),
          buildWhen: (s) => (s.state as _S).count > 1,
          builder: (_, __, ___) {
            builds++;
            return const SizedBox();
          },
        ),
      ));
      await _send(tester, a, _Inc(rebuildAlways));
      expect(builds, 1);
      await _send(tester, a, _Inc(rebuildAlways));
      expect(builds, 2);
      await tester.pumpWidget(const SizedBox());
      expect(calls, ['init', 'dispose']);
      await tester.runAsync(a.close);
    });

    testWidgets('empty bloc list throws StateError', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: JuiceMultiBuilder(
          blocs: const [],
          builder: (_, __, ___) => const SizedBox(),
        ),
      ));
      final e = tester.takeException();
      expect(e, isA<StateError>());
      expect('$e', contains('at least one bloc'));
    });

    testWidgets(
        '.resolve: resolve() and lease() both take leases released on dispose',
        (tester) async {
      BlocScope.register<_A>(() => _A(), lifecycle: BlocLifecycle.leased);
      BlocScope.register<_B>(() => _B(), lifecycle: BlocLifecycle.leased);
      late List<JuiceBloc> got;
      await tester.pumpWidget(MaterialApp(
        home: JuiceMultiBuilder.resolve(
          resolve: (r) => [r.resolve<_A>(), r.lease<_B>().bloc],
          builder: (_, blocs, __) {
            got = blocs;
            return Text('${blocs.length}');
          },
        ),
      ));
      expect(find.text('2'), findsOneWidget);
      expect(got[0], isA<_A>());
      expect(got[1], isA<_B>());

      await _send(tester, got[1], _Inc(rebuildAlways));
      expect((got[1].state as _S).count, 101);

      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
      expect(got[0].isClosed, isTrue);
      expect(got[1].isClosed, isTrue);
    });

    testWidgets('.resolve: disposeAll on the tracking resolver releases leases',
        (tester) async {
      BlocScope.register<_A>(() => _A(), lifecycle: BlocLifecycle.leased);
      BlocScope.register<_B>(() => _B());
      late _A a;
      late _B b;
      await tester.pumpWidget(MaterialApp(
        home: JuiceMultiBuilder.resolve(
          resolve: (r) {
            a = r.resolve<_A>();
            r.lease<_A>();
            // Releases both tracked _A leases; the widget keeps only _B.
            r.disposeAll();
            b = r.resolve<_B>();
            return [b];
          },
          builder: (_, __, ___) => const SizedBox(),
        ),
      ));
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
      expect(a.isClosed, isTrue,
          reason: 'both leases released → leased bloc auto-closed');
      expect(b.isClosed, isFalse);

      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
      expect(b.isClosed, isFalse, reason: 'permanent bloc survives release');
    });

    testWidgets('builder errors render JuiceExceptionWidget', (tester) async {
      final a = _A();
      await tester.pumpWidget(MaterialApp(
        home: JuiceMultiBuilder(
          blocs: [a],
          builder: (_, __, ___) => throw Exception('multi'),
        ),
      ));
      expect(find.byType(JuiceExceptionWidget), findsOneWidget);
      expect(find.textContaining('multi'), findsWidgets);
      await tester.runAsync(a.close);
    });
  });
}
