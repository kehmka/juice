import 'package:flutter/foundation.dart' show listEquals;
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

  group('1.8.1 fixes', () {
    Widget host(_B bloc, {Set<String>? groups, int Function(_S)? selector}) =>
        MaterialApp(
          home: JuiceSelector<_B, _S, int>(
            bloc: bloc,
            groups: groups,
            selector: selector ?? (s) => s.count,
            builder: (_, v) => Text('v=$v'),
          ),
        );

    testWidgets('swapping the bloc shows the NEW bloc\'s value immediately',
        (tester) async {
      final b1 = _B(), b2 = _B();
      await b2.send(_SetCount(7));
      await tester.pumpWidget(host(b1));
      await tester.runAsync(() => b1.send(_SetCount(3)));
      await tester.pump();
      expect(find.text('v=3'), findsOneWidget);

      await tester.pumpWidget(host(b2));
      expect(find.text('v=7'), findsOneWidget,
          reason: 'was stuck on the old bloc\'s 3');

      // And it now follows b2, not b1.
      await tester.runAsync(() => b1.send(_SetCount(100)));
      await tester.runAsync(() => b2.send(_SetCount(8)));
      await tester.pump();
      expect(find.text('v=8'), findsOneWidget);
      await b1.close();
      await b2.close();
    });

    testWidgets('a new selector closure is applied on rebuild', (tester) async {
      final b = _B();
      await b.send(_SetCount(2));
      await tester.pumpWidget(host(b, selector: (s) => s.count));
      expect(find.text('v=2'), findsOneWidget);
      await tester.pumpWidget(host(b, selector: (s) => s.count * 10));
      expect(find.text('v=20'), findsOneWidget);
      await tester.runAsync(() => b.send(_SetCount(3)));
      await tester.pump();
      expect(find.text('v=30'), findsOneWidget);
      await b.close();
    });

    testWidgets(
        'an equal-by-value inline groups literal does not resubscribe, and '
        'a changed one takes effect', (tester) async {
      final b = _B();
      var builds = 0;
      Widget w(Set<String> groups) => MaterialApp(
            home: JuiceSelector<_B, _S, String>(
              bloc: b,
              groups: groups,
              selector: (s) => '${s.count}/${s.label}',
              builder: (_, v) {
                builds++;
                return Text(v);
              },
            ),
          );
      await tester.pumpWidget(w({_G.count}));
      await tester.pumpWidget(w({_G.count})); // new Set, same contents
      await tester.runAsync(() => b.send(_SetLabel('x')));
      await tester.pump();
      expect(find.text('0/'), findsOneWidget,
          reason: 'label is outside {count}');

      await tester.pumpWidget(w({_G.label}));
      final before = builds;
      await tester.runAsync(() => b.send(_SetLabel('y')));
      await tester.pump();
      expect(find.text('0/y'), findsOneWidget);
      expect(builds, before + 1);
      await b.close();
    });

    testWidgets('JuiceSelectorWith follows a bloc swap too', (tester) async {
      final b1 = _B(), b2 = _B();
      await b2.send(_SetCount(5));
      Widget w(_B b) => MaterialApp(
            home: JuiceSelectorWith<_B, _S, List<int>>(
              bloc: b,
              selector: (s) => [s.count],
              equals: listEquals,
              builder: (_, v) => Text('l=${v.first}'),
            ),
          );
      await tester.pumpWidget(w(b1));
      expect(find.text('l=0'), findsOneWidget);
      await tester.pumpWidget(w(b2));
      expect(find.text('l=5'), findsOneWidget);
      await b1.close();
      await b2.close();
    });
  });
}
