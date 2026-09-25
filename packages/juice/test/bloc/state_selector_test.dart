import 'package:flutter_test/flutter_test.dart';
import 'package:juice/juice.dart';

/// THE SELECTOR PINS (2026-09-21, BlocSignal tee-up #2 made real): `select`
/// existed, exported and undocumented, and listened to the RAW stream — every
/// emission on the bloc woke every selector regardless of group. Now it lives
/// inside the groups vocabulary: with `groups`, an emission outside them is
/// ignored entirely (not compared, not remembered); inside them, the projected
/// value is compared. Plus the value-equality precondition and the
/// nullable-projection fix.

class _S extends BlocState {
  final int count;
  final String label;
  final int? maybe;
  const _S({this.count = 0, this.label = '', this.maybe});
  _S copyWith({int? count, String? label, Object? maybe = _unset}) => _S(
        count: count ?? this.count,
        label: label ?? this.label,
        maybe: identical(maybe, _unset) ? this.maybe : maybe as int?,
      );
}

const Object _unset = Object();

abstract final class _G {
  static const count = 'sel:count';
  static const label = 'sel:label';
}

class _Ev extends EventBase {}

class _SetCount extends _Ev {
  final int v;
  _SetCount(this.v);
}

class _SetLabel extends _Ev {
  final String v;
  _SetLabel(this.v);
}

class _SetMaybe extends _Ev {
  final int? v;
  _SetMaybe(this.v);
}

class _BumpAll extends _Ev {
  final int v;
  _BumpAll(this.v);
}

class _BumpAllUC extends BlocUseCase<_B, _BumpAll> {
  @override
  Future<void> execute(_BumpAll e) async => emitUpdate(
      newState: bloc.state.copyWith(count: e.v),
      groupsToRebuild: rebuildAlways);
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

class _MaybeUC extends BlocUseCase<_B, _SetMaybe> {
  @override
  Future<void> execute(_SetMaybe e) async => emitUpdate(
      newState: bloc.state.copyWith(maybe: e.v), groupsToRebuild: {_G.count});
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
          () => UseCaseBuilder(
              typeOfEvent: _SetMaybe,
              useCaseGenerator: () => _MaybeUC(),
              concurrency: EventConcurrency.sequential),
          () => UseCaseBuilder(
              typeOfEvent: _BumpAll,
              useCaseGenerator: () => _BumpAllUC(),
              concurrency: EventConcurrency.sequential),
        ]);
}

void main() {
  Future<void> settle([int ms = 20]) =>
      Future<void>.delayed(Duration(milliseconds: ms));

  group('bloc.select', () {
    test(
        'does not replay; emits only on change (==), the first emission '
        'compared against the state at subscription', () async {
      final b = _B();
      final seen = <int>[];
      final sub = b.select((s) => s.count).listen(seen.add);
      await settle();
      b.send(_SetCount(0)); // equal to the seeded value → suppressed
      b.send(_SetCount(1));
      b.send(_SetCount(1)); // same value → suppressed
      b.send(_SetCount(2));
      await settle();
      expect(seen, [1, 2]);
      await sub.cancel();
      await b.close();
    });

    test(
        'WITHOUT groups, an emission on another group still wakes the '
        'selector (compared, suppressed only because the value is equal)',
        () async {
      final b = _B();
      var considered = 0;
      final sub = b.select((s) {
        considered++;
        return s.count;
      }).listen((_) {});
      await settle();
      final before = considered;
      b.send(_SetLabel('x'));
      await settle();
      expect(considered, before + 1,
          reason: 'raw-stream selection projects every emission');
      await sub.cancel();
      await b.close();
    });

    test(
        'WITH groups, an emission outside them is ignored entirely — '
        'not projected, not remembered', () async {
      final b = _B();
      var considered = 0;
      final seen = <int>[];
      final sub = b.select((s) {
        considered++;
        return s.count;
      }, groups: {_G.count}).listen(seen.add);
      await settle();
      final before = considered;
      b.send(_SetLabel('x'));
      await settle();
      expect(considered, before, reason: 'filtered by denyRebuild first');
      b.send(_SetCount(5));
      await settle();
      expect(seen, [5]);
      await sub.cancel();
      await b.close();
    });

    test('rebuildAlways reaches a grouped selector', () async {
      final b = _B();
      final seen = <int>[];
      final sub = b.select((s) => s.count, groups: {_G.label}).listen(seen.add);
      await settle();
      b.send(_SetCount(1)); // count group: filtered
      b.send(_BumpAll(9)); // rebuildAlways: passes the group filter
      await settle();
      expect(seen, [9]);
      await sub.cancel();
      await b.close();
    });

    test(
        'selectWith: a nullable projection dedupes (the old null guard '
        're-emitted on every emission)', () async {
      final b = _B();
      final seen = <int?>[];
      final sub = b.selectWith<int?>((s) => s.maybe,
          equals: (a, c) => a == c, groups: {_G.count}).listen(seen.add);
      await settle();
      b.send(_SetMaybe(null)); // null → null: suppressed
      b.send(_SetMaybe(3));
      b.send(_SetMaybe(3)); // suppressed
      b.send(_SetMaybe(null)); // 3 → null: emits
      await settle();
      expect(seen, [3, null]);
      await sub.cancel();
      await b.close();
    });
  });

  group('1.8.1 fixes', () {
    test(
        'two listeners on the SAME selected stream each get every change '
        '(previous is per subscription, not shared)', () async {
      final b = _B();
      final selected = b.select((s) => s.count);
      final first = <int>[], second = <int>[];
      final s1 = selected.listen(first.add);
      final s2 = selected.listen(second.add);
      b.send(_SetCount(1));
      b.send(_SetCount(2));
      await settle();
      expect(first, [1, 2]);
      expect(second, [1, 2]);
      await s1.cancel();
      await s2.cancel();
      await b.close();
    });

    test('a late listener is seeded from the state when IT subscribes',
        () async {
      final b = _B();
      final selected = b.select((s) => s.count);
      b.send(_SetCount(5));
      await settle();
      final seen = <int>[];
      final sub = selected.listen(seen.add);
      b.send(_SetCount(5)); // equal to the state at subscription → suppressed
      b.send(_SetCount(6));
      await settle();
      expect(seen, [6]);
      await sub.cancel();
      await b.close();
    });

    test('the selected stream stays broadcast', () {
      final b = _B();
      expect(b.select((s) => s.count).isBroadcast, isTrue);
      b.close();
    });
  });

  group('sendAndWait', () {
    test('returns the event\'s own terminal status (was: always timed out)',
        () async {
      final b = _B();
      final event = _SetCount(4);
      final status =
          await b.sendAndWait(event, timeout: const Duration(seconds: 2));
      expect(status, isA<UpdatingStatus<_S>>());
      expect(identical(status.event, event), isTrue);
      expect(b.state.count, 4);
      await b.close();
    });

    test('ignores emissions caused by other events', () async {
      final b = _B();
      final other = b.send(_SetLabel('x'));
      final status = await b.sendAndWait(_SetCount(9),
          timeout: const Duration(seconds: 2));
      await other;
      expect(status.event, isA<_SetCount>());
      await b.close();
    });
  });
}
