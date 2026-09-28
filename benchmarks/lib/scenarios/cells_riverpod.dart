import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../counters.dart';
import 'variant.dart';

class CellsNotifier extends Notifier<List<int>> {
  CellsNotifier(this.cells);
  final int cells;

  @override
  List<int> build() => List<int>.filled(cells, 0);

  void set(int index, int value) =>
      state = List<int>.of(state)..[index] = value;
}

/// Riverpod with `select` per cell — the idiomatic form.
class RiverpodSelectVariant extends Variant {
  @override
  String get name => 'riverpod · select';
  @override
  String get framework => 'riverpod';
  @override
  String get mechanism => 'consumer-side select + ==';

  late NotifierProvider<CellsNotifier, List<int>> provider;
  late ProviderContainer container;

  @override
  void setUp(int cells) {
    provider = NotifierProvider<CellsNotifier, List<int>>(
      () => CellsNotifier(cells),
    );
    container = ProviderContainer();
  }

  Widget cell(int i) => Consumer(
    builder: (_, ref, __) {
      final v = ref.watch(
        provider.select((s) {
          Counters.selectorCalls++;
          return s[i];
        }),
      );
      Counters.builds[i]++;
      return cellText(v);
    },
  );

  @override
  Widget build(int cells) => UncontrolledProviderScope(
    container: container,
    child: Wrap(children: [for (var i = 0; i < cells; i++) cell(i)]),
  );

  @override
  Future<void> update(int index, int value) async {
    // Riverpod has no event queue: a method call updates state synchronously.
    container.read(provider.notifier).set(index, value);
  }

  @override
  Future<void> tearDown() async => container.dispose();
}

/// Riverpod watching the whole list — every change rebuilds every consumer.
class RiverpodWatchVariant extends RiverpodSelectVariant {
  @override
  String get name => 'riverpod · watch';
  @override
  String get mechanism => 'no filter (the default)';

  @override
  Widget cell(int i) => Consumer(
    builder: (_, ref, __) {
      final v = ref.watch(provider)[i];
      Counters.builds[i]++;
      return cellText(v);
    },
  );
}
