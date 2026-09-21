import 'package:flutter_test/flutter_test.dart';
import 'package:juice/juice.dart';

/// Widget-level pins for `JuiceSelector` inside the groups vocabulary: the
/// builder runs when an emission targets the widget's group AND the selected
/// value changed — and not otherwise.

class _S extends BlocState {
  final int count;
  final String label;
  const _S({this.count = 0, this.label = ''});
  _S copyWith({int? count, String? label}) =>
      _S(count: count ?? this.count, label: label ?? this.label);
}

abstract final class _G {
  static const count = 'w:count';
  static const label = 'w:label';
}

class _SetCount extends EventBase {
  final int v;
  _SetCount(this.v);
}

class _SetLabel extends EventBase {
  final String v;
  _SetLabel(this.v);
}

class _CountUC extends BlocUseCase<_B, _SetCount> {
  @override
  Future<void> execute(_SetCount e) async => emitUpdate(
      newState: bloc.state.copyWith(count: e.v), groupsToRebuild: {_G.count});
}

class _LabelUC extends BlocUseCase<_B, _SetLabel> {
  @override
  Future<void> execute(_SetLabel e) async => emitUpdate(
      newState: bloc.state.copyWith(label: e.v), groupsToRebuild: {_G.label});
}

class _B extends JuiceBloc<_S> {
  _B()
      : super(const _S(), [
          () => UseCaseBuilder(
              typeOfEvent: _SetCount,
              useCaseGenerator: () => _CountUC(),
              concurrency: EventConcurrency.sequential),
          () => UseCaseBuilder(
              typeOfEvent: _SetLabel,
              useCaseGenerator: () => _LabelUC(),
              concurrency: EventConcurrency.sequential),
        ]);
}

void main() {
  setUp(BlocScope.reset);
  tearDown(BlocScope.reset);

  Future<int> pumpSelector(WidgetTester tester, _B bloc,
      {Set<String>? groups}) async {
    var builds = 0;
    await tester.pumpWidget(MaterialApp(
      home: JuiceSelector<_B, _S, int>(
        bloc: bloc,
        groups: groups,
        selector: (s) => s.count,
        builder: (_, count) {
          builds++;
          return Text('$count');
        },
      ),
    ));
    return builds;
  }

  testWidgets('grouped: rebuilds on its group when the value changes',
      (tester) async {
    final b = _B();
    await pumpSelector(tester, b, groups: {_G.count});
    expect(find.text('0'), findsOneWidget);
    b.send(_SetCount(7));
    await tester.pump();
    await tester.pump();
    expect(find.text('7'), findsOneWidget);
    await b.close();
  });

  testWidgets(
      'grouped: an emission on ANOTHER group does not rebuild it, '
      'even though the bloc emitted', (tester) async {
    final b = _B();
    var builds = 0;
    await tester.pumpWidget(MaterialApp(
      home: JuiceSelector<_B, _S, int>(
        bloc: b,
        groups: const {_G.count},
        selector: (s) => s.count,
        builder: (_, c) {
          builds++;
          return Text('$c');
        },
      ),
    ));
    final after = builds;
    b.send(_SetLabel('changed'));
    await tester.pump();
    await tester.pump();
    expect(builds, after, reason: 'label group is outside the selector');
    await b.close();
  });

  testWidgets('grouped: same value on its own group does not rebuild',
      (tester) async {
    final b = _B();
    var builds = 0;
    await tester.pumpWidget(MaterialApp(
      home: JuiceSelector<_B, _S, int>(
        bloc: b,
        groups: const {_G.count},
        selector: (s) => s.count,
        builder: (_, c) {
          builds++;
          return Text('$c');
        },
      ),
    ));
    final after = builds;
    b.send(_SetCount(0)); // equal to current
    await tester.pump();
    await tester.pump();
    expect(builds, after);
    await b.close();
  });

  testWidgets('ungrouped (legacy): still works, compares every emission',
      (tester) async {
    final b = _B();
    await pumpSelector(tester, b);
    b.send(_SetCount(3));
    await tester.pump();
    await tester.pump();
    expect(find.text('3'), findsOneWidget);
    await b.close();
  });
}
