import 'package:flutter_bloc/flutter_bloc.dart' as fb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show NotifierProviderFamily;
import 'package:juice/juice.dart';

import '../counters.dart';
import 'variant.dart';

/// THE WIDE SCENARIO — built to stress what groups do NOT help with.
///
/// Groups put the cost of targeting on the EMITTER, which must name every
/// consumer; selectors put it on CONSUMERS, which decide for themselves.
/// That trade turns against groups when one update legitimately touches
/// many widgets and a cross-cutting derived view:
///
/// - N cells (ints) plus one HEADER showing the sum over every cell;
/// - one update sets a run of K = N ~/ 20 consecutive cells (5 of 100,
///   50 of 1000) — so K cells AND the header change on every update.
///
/// Fixed in advance: tuned forms build K + 1 widgets per update, naive
/// forms N + 1. Selector forms run N + 1 selectors per update; groups run
/// none, but the emitter names K + 1 groups. Which side pays, and how much,
/// is what the frame numbers measure.
int wideK(int cells) => cells ~/ 20 < 1 ? 1 : cells ~/ 20;

int sumOf(List<int> cells) => cells.fold(0, (a, b) => a + b);

List<int> withRun(List<int> cells, int start, int k, int value) {
  final next = List<int>.of(cells);
  for (var j = 0; j < k; j++) {
    next[(start + j) % next.length] = value;
  }
  return next;
}

Widget headerText(int sum) =>
    Text('sum=$sum', textDirection: TextDirection.ltr);

// ----------------------------------------------------------------- Juice

class WideState extends BlocState {
  const WideState(this.cells);
  final List<int> cells;
}

abstract final class WideGroups {
  static String cell(int i) => 'cell:$i';
  static const header = 'header';
}

class SetRunEvent extends EventBase {
  SetRunEvent(this.start, this.value, {required this.grouped});
  final int start;
  final int value;
  final bool grouped;
}

class SetRunUseCase extends BlocUseCase<WideBloc, SetRunEvent> {
  @override
  Future<void> execute(SetRunEvent e) async {
    final k = wideK(bloc.state.cells.length);
    emitUpdate(
      newState: WideState(withRun(bloc.state.cells, e.start, k, e.value)),
      // Tuned: the emitter names every consumer that changed — K cells and
      // the header. Naive: no groups, rebuildAlways.
      groupsToRebuild: e.grouped
          ? {
              for (var j = 0; j < k; j++)
                WideGroups.cell((e.start + j) % bloc.state.cells.length),
              WideGroups.header,
            }
          : null,
    );
  }
}

class WideBloc extends JuiceBloc<WideState> {
  WideBloc(int cells)
    : super(WideState(List<int>.filled(cells, 0)), [
        () => UseCaseBuilder.typed(
          () => SetRunUseCase(),
          concurrency: EventConcurrency.concurrent,
        ),
      ]);
}

class _JuiceCell extends StatelessJuiceWidget<WideBloc> {
  _JuiceCell(this.index, {super.groups});
  final int index;
  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    Counters.builds[index]++;
    return cellText(bloc.state.cells[index]);
  }
}

class _JuiceHeader extends StatelessJuiceWidget<WideBloc> {
  _JuiceHeader({super.groups});
  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    Counters.headerBuilds++;
    return headerText(sumOf(bloc.state.cells));
  }
}

class WideJuiceGroupsVariant extends Variant {
  @override
  String get name => 'wide · juice · groups';
  @override
  String get framework => 'juice';
  @override
  String get mechanism => 'emitter names K cells + header';

  late WideBloc bloc;
  @override
  void setUp(int cells) {
    bloc = WideBloc(cells);
    BlocScope.register<WideBloc>(() => bloc);
  }

  @override
  Widget build(int cells) => Column(
    children: [
      _JuiceHeader(groups: const {WideGroups.header}),
      Wrap(
        children: [
          for (var i = 0; i < cells; i++)
            _JuiceCell(i, groups: {WideGroups.cell(i)}),
        ],
      ),
    ],
  );

  @override
  Future<void> update(int index, int value) =>
      bloc.send(SetRunEvent(index, value, grouped: true));
  @override
  Future<void> tearDown() => BlocScope.endAll();
}

class WideJuiceSelectorVariant extends WideJuiceGroupsVariant {
  @override
  String get name => 'wide · juice · JuiceSelector + groups';
  @override
  String get mechanism => 'group filter, then selector, per cell + header';

  @override
  Widget build(int cells) => Column(
    children: [
      JuiceSelector<WideBloc, WideState, int>(
        bloc: bloc,
        groups: const {WideGroups.header},
        selector: (s) {
          Counters.selectorCalls++;
          return sumOf(s.cells);
        },
        builder: (_, sum) {
          Counters.headerBuilds++;
          return headerText(sum);
        },
      ),
      Wrap(
        children: [
          for (var i = 0; i < cells; i++)
            JuiceSelector<WideBloc, WideState, int>(
              bloc: bloc,
              groups: {WideGroups.cell(i)},
              selector: (s) {
                Counters.selectorCalls++;
                return s.cells[i];
              },
              builder: (_, v) {
                Counters.builds[i]++;
                return cellText(v);
              },
            ),
        ],
      ),
    ],
  );
}

class WideJuiceUngroupedVariant extends WideJuiceGroupsVariant {
  @override
  String get name => 'wide · juice · no groups';
  @override
  String get mechanism => 'rebuildAlways broadcast (the default)';

  @override
  Widget build(int cells) => Column(
    children: [
      _JuiceHeader(),
      Wrap(children: [for (var i = 0; i < cells; i++) _JuiceCell(i)]),
    ],
  );
  @override
  Future<void> update(int index, int value) =>
      bloc.send(SetRunEvent(index, value, grouped: false));
}

// ------------------------------------------------------------------ bloc

class SetRun {
  SetRun(this.start, this.value);
  final int start;
  final int value;
}

class WideCellsBloc extends fb.Bloc<SetRun, List<int>> {
  WideCellsBloc(int cells) : super(List<int>.filled(cells, 0)) {
    on<SetRun>(
      (e, emit) => emit(withRun(state, e.start, wideK(state.length), e.value)),
    );
  }
}

class WideBlocSelectorVariant extends Variant {
  @override
  String get name => 'wide · bloc · BlocSelector';
  @override
  String get framework => 'bloc';
  @override
  String get mechanism => 'selector per cell + header';

  late WideCellsBloc bloc;
  @override
  void setUp(int cells) => bloc = WideCellsBloc(cells);

  Widget header() => fb.BlocSelector<WideCellsBloc, List<int>, int>(
    selector: (s) {
      Counters.selectorCalls++;
      return sumOf(s);
    },
    builder: (_, sum) {
      Counters.headerBuilds++;
      return headerText(sum);
    },
  );

  Widget cell(int i) => fb.BlocSelector<WideCellsBloc, List<int>, int>(
    selector: (s) {
      Counters.selectorCalls++;
      return s[i];
    },
    builder: (_, v) {
      Counters.builds[i]++;
      return cellText(v);
    },
  );

  @override
  Widget build(int cells) => fb.BlocProvider<WideCellsBloc>.value(
    value: bloc,
    child: Column(
      children: [
        header(),
        Wrap(children: [for (var i = 0; i < cells; i++) cell(i)]),
      ],
    ),
  );

  @override
  Future<void> update(int index, int value) {
    final next = bloc.stream.first;
    bloc.add(SetRun(index, value));
    return next;
  }

  @override
  Future<void> tearDown() => bloc.close();
}

class WideBlocBuilderVariant extends WideBlocSelectorVariant {
  @override
  String get name => 'wide · bloc · BlocBuilder';
  @override
  String get mechanism => 'no filter (the default)';

  @override
  Widget header() => fb.BlocBuilder<WideCellsBloc, List<int>>(
    builder: (_, s) {
      Counters.headerBuilds++;
      return headerText(sumOf(s));
    },
  );
  @override
  Widget cell(int i) => fb.BlocBuilder<WideCellsBloc, List<int>>(
    builder: (_, s) {
      Counters.builds[i]++;
      return cellText(s[i]);
    },
  );
}

// -------------------------------------------------------------- riverpod

class WideNotifier extends Notifier<List<int>> {
  WideNotifier(this.cells);
  final int cells;
  @override
  List<int> build() => List<int>.filled(cells, 0);
  void setRun(int start, int value) =>
      state = withRun(state, start, wideK(state.length), value);
}

class WideRiverpodSelectVariant extends Variant {
  @override
  String get name => 'wide · riverpod · select';
  @override
  String get framework => 'riverpod';
  @override
  String get mechanism => 'select per cell + header';

  late NotifierProvider<WideNotifier, List<int>> provider;
  late ProviderContainer container;
  @override
  void setUp(int cells) {
    provider = NotifierProvider<WideNotifier, List<int>>(
      () => WideNotifier(cells),
    );
    container = ProviderContainer();
  }

  Widget header() => Consumer(
    builder: (_, ref, __) {
      final sum = ref.watch(
        provider.select((s) {
          Counters.selectorCalls++;
          return sumOf(s);
        }),
      );
      Counters.headerBuilds++;
      return headerText(sum);
    },
  );

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
    child: Column(
      children: [
        header(),
        Wrap(children: [for (var i = 0; i < cells; i++) cell(i)]),
      ],
    ),
  );

  @override
  Future<void> update(int index, int value) async =>
      container.read(provider.notifier).setRun(index, value);
  @override
  Future<void> tearDown() async => container.dispose();
}

class WideRiverpodWatchVariant extends WideRiverpodSelectVariant {
  @override
  String get name => 'wide · riverpod · watch';
  @override
  String get mechanism => 'no filter (the default)';

  @override
  Widget header() => Consumer(
    builder: (_, ref, __) {
      final sum = sumOf(ref.watch(provider));
      Counters.headerBuilds++;
      return headerText(sum);
    },
  );
  @override
  Widget cell(int i) => Consumer(
    builder: (_, ref, __) {
      final v = ref.watch(provider)[i];
      Counters.builds[i]++;
      return cellText(v);
    },
  );
}

/// One provider per cell plus a DERIVED sum provider that watches every
/// cell — Riverpod's other idiomatic form. This is where families meet the
/// wide scenario's cross-cutting header: K cell notifiers change per update,
/// and the sum provider must recompute over all N of them. Its recomputes
/// are counted in `Counters.selectorCalls` (each one is an O(N) derivation,
/// not an O(1) selector — read the column with that in mind), and the
/// update sets the K cells one provider at a time, as a family forces.
class WideCellNotifier extends Notifier<int> {
  WideCellNotifier(this.index);
  final int index;
  @override
  int build() => 0;
  void set(int value) => state = value;
}

class WideRiverpodFamilyVariant extends Variant {
  @override
  String get name => 'wide · riverpod · family';
  @override
  String get framework => 'riverpod';
  @override
  String get mechanism => 'family per cell + derived sum provider';

  late NotifierProviderFamily<WideCellNotifier, int, int> cellProvider;
  late Provider<int> sumProvider;
  late ProviderContainer container;
  late int cells;

  @override
  void setUp(int cells) {
    this.cells = cells;
    cellProvider = NotifierProvider.family<WideCellNotifier, int, int>(
      WideCellNotifier.new,
    );
    sumProvider = Provider<int>((ref) {
      Counters.selectorCalls++; // one O(N) recompute
      var sum = 0;
      for (var i = 0; i < cells; i++) {
        sum += ref.watch(cellProvider(i));
      }
      return sum;
    });
    container = ProviderContainer();
  }

  Widget header() => Consumer(
    builder: (_, ref, __) {
      final sum = ref.watch(sumProvider);
      Counters.headerBuilds++;
      return headerText(sum);
    },
  );

  Widget cell(int i) => Consumer(
    builder: (_, ref, __) {
      final v = ref.watch(cellProvider(i));
      Counters.builds[i]++;
      return cellText(v);
    },
  );

  @override
  Widget build(int cells) => UncontrolledProviderScope(
    container: container,
    child: Column(
      children: [
        header(),
        Wrap(children: [for (var i = 0; i < cells; i++) cell(i)]),
      ],
    ),
  );

  @override
  Future<void> update(int index, int value) async {
    final k = wideK(cells);
    for (var j = 0; j < k; j++) {
      container.read(cellProvider((index + j) % cells).notifier).set(value);
    }
  }

  @override
  Future<void> tearDown() async => container.dispose();
}

/// Every wide variant, tuned first within each framework.
List<Variant> wideVariants() => [
  WideJuiceGroupsVariant(),
  WideJuiceSelectorVariant(),
  WideJuiceUngroupedVariant(),
  WideBlocSelectorVariant(),
  WideBlocBuilderVariant(),
  WideRiverpodFamilyVariant(),
  WideRiverpodSelectVariant(),
  WideRiverpodWatchVariant(),
];
