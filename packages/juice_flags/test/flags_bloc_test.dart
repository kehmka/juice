import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:juice_flags/juice_flags.dart';

/// Records emitted rebuild groups, to assert per-flag selective refresh.
class GroupRecorder {
  final List<Set<String>> emissions = [];
  late final StreamSubscription _sub;
  GroupRecorder(FlagsBloc bloc) {
    _sub = bloc.stream.listen((status) {
      final g = status.event?.groupsToRebuild;
      if (g != null) emissions.add(g);
    });
  }
  Set<String> get last => emissions.last;
  void clear() => emissions.clear();
  Future<void> cancel() => _sub.cancel();
}

/// Controllable fake source: fetch returns [next]; optional live stream.
class FakeFlagsSource implements FlagsSource {
  Map<String, Object?> next;
  Object? fetchError;
  bool disposed = false;
  final _controller = StreamController<Map<String, Object?>>.broadcast();

  FakeFlagsSource([this.next = const {}]);

  @override
  Future<Map<String, Object?>> fetch() async {
    if (fetchError != null) throw fetchError!;
    return Map.of(next);
  }

  @override
  Stream<Map<String, Object?>>? changes() => _controller.stream;

  void push(Map<String, Object?> values) => _controller.add(values);

  @override
  Future<void> dispose() async {
    disposed = true;
    await _controller.close();
  }
}

void main() {
  Future<void> settle([int ms = 20]) =>
      Future<void>.delayed(Duration(milliseconds: ms));

  group('FlagsState model', () {
    test('defaults', () {
      const s = FlagsState();
      expect(s.values, isEmpty);
      expect(s.loading, isFalse);
      expect(s.fetched, isFalse);
      expect(s.error, isNull);
    });
  });

  group('Defaults & typed reads', () {
    test('reads resolve to defaults before any fetch', () async {
      final src = FakeFlagsSource();
      final bloc = FlagsBloc.withConfig(FlagsConfig(
        source: src,
        defaults: {'enabled': true, 'max': 20, 'name': 'hi', 'ratio': 0.5},
        fetchOnInit: false,
      ));
      await settle();

      expect(bloc.boolFlag('enabled'), isTrue);
      expect(bloc.intFlag('max'), 20);
      expect(bloc.stringFlag('name'), 'hi');
      expect(bloc.doubleFlag('ratio'), 0.5);
      // Unknown key falls back.
      expect(bloc.boolFlag('missing', fallback: true), isTrue);

      await bloc.close();
    });

    test('fetched value overlays the default', () async {
      final src = FakeFlagsSource({'enabled': true});
      final bloc = FlagsBloc.withConfig(FlagsConfig(
        source: src,
        defaults: {'enabled': false},
      ));
      await settle();

      expect(bloc.boolFlag('enabled'), isTrue); // fetched wins over default
      expect(bloc.state.fetched, isTrue);

      await bloc.close();
    });
  });

  group('Diff-on-fetch selective refresh', () {
    test('only changed flags emit their group', () async {
      final src = FakeFlagsSource({'a': 1, 'b': 2, 'c': 3});
      final bloc = FlagsBloc.withConfig(FlagsConfig(
        source: src,
        defaults: {'a': 1, 'b': 2, 'c': 3},
        fetchOnInit: false,
      ));
      await settle();

      final rec = GroupRecorder(bloc);
      // Next fetch changes only 'b'.
      src.next = {'a': 1, 'b': 99, 'c': 3};
      bloc.refresh();
      await settle();

      // The value-emission (not the loading one) carries the per-flag groups.
      final valueEmit =
          rec.emissions.firstWhere((g) => g.contains(FlagsGroups.any));
      expect(valueEmit, contains(FlagsGroups.flag('b')));
      expect(valueEmit, isNot(contains(FlagsGroups.flag('a'))));
      expect(valueEmit, isNot(contains(FlagsGroups.flag('c'))));
      expect(bloc.intFlag('b'), 99);

      await rec.cancel();
      await bloc.close();
    });
  });

  group('Fetch failure (fail-loud, read-safe)', () {
    test('error surfaces but reads keep falling back', () async {
      final src = FakeFlagsSource()..fetchError = StateError('network down');
      final bloc = FlagsBloc.withConfig(FlagsConfig(
        source: src,
        defaults: {'enabled': true},
      ));
      await settle();

      expect(bloc.state.error, contains('network down'));
      expect(bloc.state.loading, isFalse);
      // Read still resolves to the default — a flag must always resolve.
      expect(bloc.boolFlag('enabled'), isTrue);

      await bloc.close();
    });
  });

  group('Live updates', () {
    test('changes() stream updates only changed flags', () async {
      final src = FakeFlagsSource({'a': 1});
      final bloc = FlagsBloc.withConfig(FlagsConfig(
        source: src,
        defaults: {'a': 1},
        fetchOnInit: false,
      ));
      await settle();

      final rec = GroupRecorder(bloc);
      src.push({'a': 1, 'b': 7}); // 'b' is new
      await settle();

      expect(bloc.intFlag('b'), 7);
      expect(rec.last, contains(FlagsGroups.flag('b')));
      expect(rec.last, isNot(contains(FlagsGroups.flag('a'))));

      await rec.cancel();
      await bloc.close();
    });
  });

  group('Overrides', () {
    test('override wins, then clears back to fetched/default', () async {
      final src = FakeFlagsSource({'enabled': false});
      final bloc = FlagsBloc.withConfig(FlagsConfig(
        source: src,
        defaults: {'enabled': false},
      ));
      await settle();
      expect(bloc.boolFlag('enabled'), isFalse);

      bloc.setFlagOverride('enabled', true);
      await settle();
      expect(bloc.boolFlag('enabled'), isTrue);

      bloc.clearFlagOverride('enabled');
      await settle();
      expect(bloc.boolFlag('enabled'), isFalse);

      await bloc.close();
    });
  });

  group('Lifecycle', () {
    test('close disposes the source', () async {
      final src = FakeFlagsSource();
      final bloc = FlagsBloc.withConfig(FlagsConfig(source: src, fetchOnInit: false));
      await settle();
      await bloc.close();
      expect(src.disposed, isTrue);
    });
  });
}
