import 'package:flutter_test/flutter_test.dart';
import 'package:juice/juice.dart';

/// 2.0 docket item H: a Juice widget keeps its bloc subscription across
/// PARENT rebuilds. Before 2.0.0 every form built a new filtered stream in
/// `build`, so each parent rebuild cancelled and re-listened (N+1 listens
/// for N rebuilds). Now the subscription is kept while the bloc, the groups
/// and the key are unchanged — and replaced when any of them changes.
///
/// The count comes from a bloc whose `stream` getter is wrapped to count
/// `listen()` calls (the only observable the churn has).

class _S extends BlocState {
  const _S(this.n);
  final int n;
}

class _Bump extends EventBase {
  _Bump() : super(groupsToRebuild: {'g'});
}

class _BumpUC extends BlocUseCase<_B, _Bump> {
  @override
  Future<void> execute(_Bump e) async =>
      emitUpdate(newState: _S(bloc.state.n + 1), groupsToRebuild: {'g'});
}

/// Counts every `listen()` on the bloc's status stream.
class _CountingStream extends StreamView<StreamStatus<_S>> {
  _CountingStream(super.inner, this.onListen);
  final void Function() onListen;
  @override
  StreamSubscription<StreamStatus<_S>> listen(
    void Function(StreamStatus<_S> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    onListen();
    return super.listen(onData,
        onError: onError, onDone: onDone, cancelOnError: cancelOnError);
  }
}

class _B extends JuiceBloc<_S> {
  _B()
      : super(const _S(0), [
          () => UseCaseBuilder.typed(() => _BumpUC(),
              concurrency: EventConcurrency.sequential),
        ]);
  int listens = 0;
  @override
  Stream<StreamStatus<_S>> get stream =>
      _CountingStream(super.stream, () => listens++);
}

/// Second and third bloc types for the two- and three-bloc widget forms.
class _B2 extends _B {}

class _B3 extends _B {}

class _Leaf2 extends StatelessJuiceWidget2<_B, _B2> {
  _Leaf2({super.groups});
  @override
  Widget onBuild(BuildContext context, StreamStatus status) =>
      Text('${bloc1.state.n}+${bloc2.state.n}',
          textDirection: TextDirection.ltr);
}

class _Leaf3 extends StatelessJuiceWidget3<_B, _B2, _B3> {
  _Leaf3({super.groups});
  @override
  Widget onBuild(BuildContext context, StreamStatus status) =>
      Text('${bloc1.state.n}+${bloc2.state.n}+${bloc3.state.n}',
          textDirection: TextDirection.ltr);
}

class _StatefulLeaf2 extends StatefulWidget {
  const _StatefulLeaf2(this.tick);
  final int tick;
  @override
  State<_StatefulLeaf2> createState() => _StatefulLeaf2State();
}

class _StatefulLeaf2State extends JuiceWidgetState2<_B, _B2, _StatefulLeaf2> {
  _StatefulLeaf2State() : super(groups: {'g'});
  @override
  Widget onBuild(BuildContext context, StreamStatus status) =>
      Text('${bloc1.state.n}+${bloc2.state.n}',
          textDirection: TextDirection.ltr);
}

class _StatefulLeaf3 extends StatefulWidget {
  const _StatefulLeaf3(this.tick);
  final int tick;
  @override
  State<_StatefulLeaf3> createState() => _StatefulLeaf3State();
}

class _StatefulLeaf3State
    extends JuiceWidgetState3<_B, _B2, _B3, _StatefulLeaf3> {
  _StatefulLeaf3State() : super(groups: {'g'});
  @override
  Widget onBuild(BuildContext context, StreamStatus status) =>
      Text('${bloc1.state.n}+${bloc2.state.n}+${bloc3.state.n}',
          textDirection: TextDirection.ltr);
}

class _Leaf extends StatelessJuiceWidget<_B> {
  _Leaf({super.groups});
  @override
  Widget onBuild(BuildContext context, StreamStatus status) =>
      Text('${bloc.state.n}', textDirection: TextDirection.ltr);
}

/// Not const: every parent rebuild hands the State a NEW widget instance.
class _StatefulLeaf extends StatefulWidget {
  const _StatefulLeaf(this.tick);
  final int tick;
  @override
  State<_StatefulLeaf> createState() => _StatefulLeafState();
}

class _StatefulLeafState extends JuiceWidgetState<_B, _StatefulLeaf> {
  _StatefulLeafState() : super(groups: {'g'});
  @override
  Widget onBuild(BuildContext context, StreamStatus status) =>
      Text('${bloc.state.n}', textDirection: TextDirection.ltr);
}

/// A parent that rebuilds its child on demand.
class _Parent extends StatefulWidget {
  const _Parent({required this.child, super.key});
  final Widget Function(int tick) child;
  @override
  State<_Parent> createState() => _ParentState();
}

class _ParentState extends State<_Parent> {
  int tick = 0;
  void rebuild() => setState(() => tick++);
  @override
  Widget build(BuildContext context) => widget.child(tick);
}

void main() {
  late _B bloc;
  late _B2 bloc2;
  late _B3 bloc3;
  setUp(() {
    bloc = _B();
    bloc2 = _B2();
    bloc3 = _B3();
    BlocScope.register<_B>(() => bloc);
    BlocScope.register<_B2>(() => bloc2);
    BlocScope.register<_B3>(() => bloc3);
  });
  tearDown(() async {
    await BlocScope.endAll();
  });

  Future<_ParentState> mount(
      WidgetTester tester, Widget Function(int tick) child) async {
    final key = GlobalKey<_ParentState>();
    await tester.pumpWidget(Directionality(
        textDirection: TextDirection.ltr,
        child: _Parent(key: key, child: child)));
    return key.currentState!;
  }

  testWidgets(
      'StatelessJuiceWidget: 10 parent rebuilds keep the ONE '
      'subscription, and emissions still arrive', (tester) async {
    final parent = await mount(tester, (_) => _Leaf(groups: const {'g'}));
    expect(bloc.listens, 1);
    for (var i = 0; i < 10; i++) {
      parent.rebuild();
      await tester.pump();
    }
    expect(bloc.listens, 1, reason: 'no re-listen per parent rebuild');
    await bloc.send(_Bump());
    await tester.pump();
    expect(find.text('1'), findsOneWidget);
    expect(bloc.listens, 1);
  });

  testWidgets(
      'JuiceWidgetState: 10 parent rebuilds keep the ONE '
      'subscription', (tester) async {
    final parent = await mount(tester, (tick) => _StatefulLeaf(tick));
    expect(bloc.listens, 1);
    for (var i = 0; i < 10; i++) {
      parent.rebuild();
      await tester.pump();
    }
    expect(bloc.listens, 1);
    await bloc.send(_Bump());
    await tester.pump();
    expect(find.text('1'), findsOneWidget);
  });

  testWidgets(
      'a parent rebuild that CHANGES the groups keeps the subscription, and '
      'the NEW widget\'s filter applies to it', (tester) async {
    final parent = await mount(tester,
        (tick) => _Leaf(groups: tick == 0 ? const {'g'} : const {'other'}));
    expect(bloc.listens, 1);
    parent.rebuild(); // groups change → same subscription, live filter
    await tester.pump();
    expect(bloc.listens, 1, reason: 'the filter is read per item, not keyed');
    await bloc.send(_Bump()); // group 'g' — the widget now listens to 'other'
    await tester.pump();
    expect(find.text('0'), findsOneWidget, reason: 'filtered out');
  });

  group('two- and three-bloc forms', () {
    Future<void> tenRebuilds(_ParentState parent, WidgetTester tester) async {
      for (var i = 0; i < 10; i++) {
        parent.rebuild();
        await tester.pump();
      }
    }

    testWidgets('StatelessJuiceWidget2 keeps ONE subscription per bloc',
        (tester) async {
      final parent = await mount(tester, (_) => _Leaf2(groups: const {'g'}));
      await tenRebuilds(parent, tester);
      expect(bloc.listens, 1);
      expect(bloc2.listens, 1);
      await bloc2.send(_Bump());
      await tester.pump();
      expect(find.text('0+1'), findsOneWidget);
    });

    testWidgets('StatelessJuiceWidget3 keeps ONE subscription per bloc',
        (tester) async {
      final parent = await mount(tester, (_) => _Leaf3(groups: const {'g'}));
      await tenRebuilds(parent, tester);
      expect([bloc.listens, bloc2.listens, bloc3.listens], [1, 1, 1]);
      await bloc3.send(_Bump());
      await tester.pump();
      expect(find.text('0+0+1'), findsOneWidget);
    });

    testWidgets('JuiceWidgetState2 keeps ONE subscription per bloc',
        (tester) async {
      final parent = await mount(tester, (tick) => _StatefulLeaf2(tick));
      await tenRebuilds(parent, tester);
      expect(bloc.listens, 1);
      expect(bloc2.listens, 1);
      await bloc2.send(_Bump());
      await tester.pump();
      expect(find.text('0+1'), findsOneWidget);
    });

    testWidgets('JuiceWidgetState3 keeps ONE subscription per bloc',
        (tester) async {
      final parent = await mount(tester, (tick) => _StatefulLeaf3(tick));
      await tenRebuilds(parent, tester);
      expect([bloc.listens, bloc2.listens, bloc3.listens], [1, 1, 1]);
      await bloc3.send(_Bump());
      await tester.pump();
      expect(find.text('0+0+1'), findsOneWidget);
    });
  });
}
