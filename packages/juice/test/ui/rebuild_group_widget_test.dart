import 'package:flutter_test/flutter_test.dart';
import 'package:juice/juice.dart';

import 'juice_widget_test_support.dart';

/// Pins for the rebuild-group vocabulary as widgets consume it: `denyRebuild`
/// edge cases, `RebuildGroup` value semantics, and typed groups driving a
/// real widget rebuild.

abstract final class _Groups {
  static const header = RebuildGroup('w:header');
  static const body = RebuildGroup('w:body');
}

class _Header extends StatelessJuiceWidget<BlocA> {
  _Header(this.builds) : super(groups: _Groups.header.toSet());
  final List<int> builds;

  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    builds.add(bloc.state.v);
    return Text('h${bloc.state.v}');
  }
}

class _Plain extends EventBase {}

void main() {
  group('denyRebuild', () {
    test('no event, or an event without groups, never rebuilds', () {
      expect(denyRebuild(rebuildGroups: rebuildAlways), isTrue);
      expect(denyRebuild(event: _Plain(), rebuildGroups: {'a'}), isTrue);
      expect(
          denyRebuild(
              event: _Plain()..groupsToRebuild = <String>{},
              rebuildGroups: {'a'}),
          isTrue);
    });

    test('intersection or an emitted "*" allows; optOut always denies', () {
      final e = _Plain()..groupsToRebuild = {'a', 'b'};
      expect(denyRebuild(event: e, rebuildGroups: {'b', 'z'}), isFalse);
      expect(denyRebuild(event: e, rebuildGroups: {'z'}), isTrue);

      final all = _Plain()..groupsToRebuild = rebuildAlways;
      expect(denyRebuild(event: all, rebuildGroups: {'z'}), isFalse);
      expect(denyRebuild(event: all, rebuildGroups: optOutOfRebuilds), isTrue);
      expect(denyRebuild(event: e, rebuildGroups: {'a', ...optOutOfRebuilds}),
          isTrue,
          reason: 'optOut wins even when another group matches');
    });
  });

  group('RebuildGroup value semantics', () {
    test('identity, name equality, foreign types, toString', () {
      const g = RebuildGroup('x');
      expect(g == g, isTrue);
      expect(g == const RebuildGroup('x'), isTrue);
      // ignore: unrelated_type_equality_checks
      expect(g == 'x', isFalse, reason: 'a String is not a RebuildGroup');
      expect(g.toString(), 'RebuildGroup(x)');
      expect(<RebuildGroup>{g}..add(const RebuildGroup('x')), hasLength(1));
    });

    test('built-ins map to the string markers', () {
      expect(RebuildGroup.all.toSet(), rebuildAlways);
      expect(RebuildGroup.optOut.toSet(), optOutOfRebuilds);
      expect(
          {_Groups.header, _Groups.body}.toStringSet(), {'w:header', 'w:body'});
    });
  });

  group('typed groups drive widgets', () {
    setUp(quietReset);
    tearDown(restoreReset);

    testWidgets('a typed-group widget rebuilds only for its group',
        (tester) async {
      BlocScope.register<BlocA>(() => BlocA());
      final builds = <int>[];
      await tester.pumpWidget(MaterialApp(home: _Header(builds)));
      final bloc = BlocScope.get<BlocA>();

      await fire(tester, bloc, WEmit(1, groups: _Groups.body.toSet()));
      await fire(tester, bloc, WEmit(2, groups: _Groups.header.toSet()));
      await fire(tester, bloc, WEmit(3, groups: RebuildGroup.all.toSet()));
      expect(builds, [0, 2, 3]);
      expect(find.text('h3'), findsOneWidget);
    });
  });
}
