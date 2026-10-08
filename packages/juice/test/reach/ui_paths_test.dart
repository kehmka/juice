import 'package:flutter_test/flutter_test.dart';
import 'package:juice/juice.dart';
import 'package:rxdart/rxdart.dart';

/// Widget paths no other test reached (coverage to 99, 2026-10-07): the
/// `error:` callback of every widget form (a bloc whose stream errors), and
/// the two- and three-bloc lease holders re-leasing when a scope changes.

class _S extends BlocState {
  const _S(this.n);
  final int n;
}

class _E extends EventBase {
  _E() : super(groupsToRebuild: {'g'});
}

class _UC extends BlocUseCase<_B, _E> {
  @override
  Future<void> execute(_E e) async =>
      emitUpdate(newState: _S(bloc.state.n + 1), groupsToRebuild: {'g'});
}

/// Its status stream can be made to ERROR on demand.
class _B extends JuiceBloc<_S> {
  _B(this.tag)
      : super(const _S(0), [
          () => UseCaseBuilder.typed(() => _UC(),
              concurrency: EventConcurrency.sequential),
        ]);
  final String tag;
  final _errors = StreamController<StreamStatus<_S>>.broadcast();
  void failStream() => _errors.addError(StateError('stream boom'));
  @override
  Stream<StreamStatus<_S>> get stream =>
      MergeStream<StreamStatus<_S>>([super.stream, _errors.stream]);
  @override
  Future<void> close() async {
    await _errors.close();
    await super.close();
  }
}

class _B2 extends _B {
  _B2(super.tag);
}

class _B3 extends _B {
  _B3(super.tag);
}

String _label(StreamStatus status) =>
    'n=${status.state is _S ? (status.state as _S).n : '?'}';

// ---- the six forms, each surfacing the error callback's status as text.
class _W1 extends StatelessJuiceWidget<_B> {
  _W1() : super(groups: const {'g'});
  @override
  Widget onBuild(BuildContext context, StreamStatus status) =>
      Text('w1 ${_label(status)}', textDirection: TextDirection.ltr);
}

class _W2 extends StatelessJuiceWidget2<_B, _B2> {
  _W2({super.scope1, super.scope2}) : super(groups: const {'g'});
  @override
  Widget onBuild(BuildContext context, StreamStatus status) =>
      Text('w2 ${bloc1.tag}/${bloc2.tag} ${_label(status)}',
          textDirection: TextDirection.ltr);
}

class _W3 extends StatelessJuiceWidget3<_B, _B2, _B3> {
  _W3({super.scope1, super.scope2, super.scope3}) : super(groups: const {'g'});
  @override
  Widget onBuild(BuildContext context, StreamStatus status) =>
      Text('w3 ${bloc1.tag}/${bloc2.tag}/${bloc3.tag} ${_label(status)}',
          textDirection: TextDirection.ltr);
}

class _SW1 extends StatefulWidget {
  const _SW1();
  @override
  State<_SW1> createState() => _SW1State();
}

class _SW1State extends JuiceWidgetState<_B, _SW1> {
  _SW1State() : super(groups: {'g'});
  @override
  Widget onBuild(BuildContext context, StreamStatus status) =>
      Text('s1 ${_label(status)}', textDirection: TextDirection.ltr);
}

class _SW2 extends StatefulWidget {
  const _SW2();
  @override
  State<_SW2> createState() => _SW2State();
}

class _SW2State extends JuiceWidgetState2<_B, _B2, _SW2> {
  _SW2State() : super(groups: {'g'});
  @override
  Widget onBuild(BuildContext context, StreamStatus status) =>
      Text('s2 ${_label(status)}', textDirection: TextDirection.ltr);
}

class _SW3 extends StatefulWidget {
  const _SW3();
  @override
  State<_SW3> createState() => _SW3State();
}

class _SW3State extends JuiceWidgetState3<_B, _B2, _B3, _SW3> {
  _SW3State() : super(groups: {'g'});
  @override
  Widget onBuild(BuildContext context, StreamStatus status) =>
      Text('s3 ${_label(status)}', textDirection: TextDirection.ltr);
}

Widget _wrap(Widget child) =>
    Directionality(textDirection: TextDirection.ltr, child: child);

void main() {
  late _B b1;
  late _B2 b2;
  late _B3 b3;
  setUp(() {
    b1 = _B('a');
    b2 = _B2('b');
    b3 = _B3('c');
    BlocScope.register<_B>(() => b1);
    BlocScope.register<_B2>(() => b2);
    BlocScope.register<_B3>(() => b3);
  });
  tearDown(() => BlocScope.endAll());

  group('the error callback renders the last status when the stream errors',
      () {
    for (final (name, widget, bloc)
        in <(String, Widget Function(), _B Function())>[
      ('StatelessJuiceWidget', () => _W1(), () => b1),
      ('StatelessJuiceWidget2', () => _W2(), () => b1),
      ('StatelessJuiceWidget3', () => _W3(), () => b1),
      ('JuiceWidgetState', () => const _SW1(), () => b1),
      ('JuiceWidgetState2', () => const _SW2(), () => b1),
      ('JuiceWidgetState3', () => const _SW3(), () => b1),
    ]) {
      testWidgets(name, (tester) async {
        await tester.pumpWidget(_wrap(widget()));
        expect(find.textContaining('n=0'), findsOneWidget);
        await bloc().send(_E());
        await tester.pump();
        expect(find.textContaining('n=1'), findsOneWidget);
        bloc().failStream();
        await tester.pump(); // the error is delivered
        await tester.pump(); // the snapshot change rebuilds through `error:`
        // The error path builds with the status the snapshot still holds.
        expect(find.textContaining('n=1'), findsOneWidget,
            reason: '$name: error callback rendered');
      });
    }
  });

  group('lease holders re-lease when a scope changes on rebuild', () {
    testWidgets('two blocs: scope1 then scope2', (tester) async {
      final a2 = _B('a2');
      final bb2 = _B2('b2');
      BlocScope.register<_B>(() => a2, scope: 's');
      BlocScope.register<_B2>(() => bb2, scope: 't');
      Object? scope1, scope2;
      late StateSetter setState;
      await tester.pumpWidget(_wrap(StatefulBuilder(builder: (context, set) {
        setState = set;
        return _W2(scope1: scope1, scope2: scope2);
      })));
      expect(find.textContaining('a/b'), findsOneWidget);
      setState(() => scope1 = 's');
      await tester.pump();
      expect(find.textContaining('a2/b'), findsOneWidget);
      expect(BlocScope.diagnostics<_B>()!.leaseCount, 0,
          reason: 'the old lease was released');
      setState(() => scope2 = 't');
      await tester.pump();
      expect(find.textContaining('a2/b2'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('three blocs: each scope in turn', (tester) async {
      final a2 = _B('a2');
      final bb2 = _B2('b2');
      final c2 = _B3('c2');
      BlocScope.register<_B>(() => a2, scope: 's');
      BlocScope.register<_B2>(() => bb2, scope: 't');
      BlocScope.register<_B3>(() => c2, scope: 'u');
      Object? s1, s2, s3;
      late StateSetter setState;
      await tester.pumpWidget(_wrap(StatefulBuilder(builder: (context, set) {
        setState = set;
        return _W3(scope1: s1, scope2: s2, scope3: s3);
      })));
      expect(find.textContaining('a/b/c'), findsOneWidget);
      setState(() => s1 = 's');
      await tester.pump();
      expect(find.textContaining('a2/b/c'), findsOneWidget);
      setState(() => s2 = 't');
      await tester.pump();
      expect(find.textContaining('a2/b2/c'), findsOneWidget);
      setState(() => s3 = 'u');
      await tester.pump();
      expect(find.textContaining('a2/b2/c2'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  });
}
