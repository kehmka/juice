import 'package:juice/juice.dart';

import '../counters.dart';
import 'variant.dart';

class CellsState extends BlocState {
  const CellsState(this.cells);
  final List<int> cells;

  CellsState withCell(int i, int v) => CellsState(List<int>.of(cells)..[i] = v);
}

abstract final class CellGroups {
  static String cell(int i) => 'cell:$i';
}

class SetCellEvent extends EventBase {
  SetCellEvent(this.index, this.value, {required this.grouped});
  final int index;
  final int value;
  final bool grouped;
}

class SetCellUseCase extends BlocUseCase<CellsBloc, SetCellEvent> {
  @override
  Future<void> execute(SetCellEvent e) async {
    emitUpdate(
      newState: bloc.state.withCell(e.index, e.value),
      // Tuned: name the one cell that changed. Naive: no groups, which
      // broadcasts to every widget (rebuildAlways).
      groupsToRebuild: e.grouped ? {CellGroups.cell(e.index)} : null,
    );
  }
}

class CellsBloc extends JuiceBloc<CellsState> {
  CellsBloc(int cells)
    : super(CellsState(List<int>.filled(cells, 0)), [
        () => UseCaseBuilder.typed(
          () => SetCellUseCase(),
          concurrency: EventConcurrency.concurrent,
        ),
      ]);
}

class _GroupedCell extends StatelessJuiceWidget<CellsBloc> {
  _GroupedCell(this.index, {super.groups});
  final int index;

  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    Counters.builds[index]++;
    return cellText(bloc.state.cells[index]);
  }
}

/// Juice with a named group per cell — the idiomatic form.
class JuiceGroupsVariant extends Variant {
  @override
  String get name => 'juice · groups';
  @override
  String get framework => 'juice';
  @override
  String get mechanism =>
      'emitter names the group; widget filters by set '
      'intersection';

  late CellsBloc bloc;

  @override
  void setUp(int cells) {
    bloc = CellsBloc(cells);
    BlocScope.register<CellsBloc>(() => bloc);
  }

  @override
  Widget build(int cells) => Wrap(
    children: [
      for (var i = 0; i < cells; i++)
        _GroupedCell(i, groups: {CellGroups.cell(i)}),
    ],
  );

  @override
  Future<void> update(int index, int value) =>
      bloc.send(SetCellEvent(index, value, grouped: true));

  @override
  // endAll closes the bloc and clears the registry for the next variant.
  Future<void> tearDown() => BlocScope.endAll();
}

/// Juice with no groups anywhere — every emission reaches every widget.
class JuiceUngroupedVariant extends JuiceGroupsVariant {
  @override
  String get name => 'juice · no groups';
  @override
  String get mechanism => 'rebuildAlways broadcast (the default)';

  @override
  Widget build(int cells) =>
      Wrap(children: [for (var i = 0; i < cells; i++) _GroupedCell(i)]);

  @override
  Future<void> update(int index, int value) =>
      bloc.send(SetCellEvent(index, value, grouped: false));
}

/// Juice with JuiceSelector and no groups — the consumer-side-select shape,
/// for direct comparison with BlocSelector / Riverpod select.
class JuiceSelectorVariant extends JuiceGroupsVariant {
  @override
  String get name => 'juice · JuiceSelector';
  @override
  String get mechanism => 'consumer-side selector + == (no groups)';

  @override
  Widget build(int cells) => Wrap(
    children: [
      for (var i = 0; i < cells; i++)
        JuiceSelector<CellsBloc, CellsState, int>(
          bloc: bloc,
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
  );

  @override
  Future<void> update(int index, int value) =>
      bloc.send(SetCellEvent(index, value, grouped: false));
}

/// JuiceSelector WITH groups — the idiomatic form since juice 1.8.0: the
/// group filter runs first (the same denyRebuild as every Juice widget), and
/// only emissions that pass it reach the selector. Expected: 1 build and
/// 1 selector call per update, where the ungrouped form runs the selector
/// in every cell.
class JuiceGroupedSelectorVariant extends JuiceGroupsVariant {
  @override
  String get name => 'juice · JuiceSelector + groups';
  @override
  String get mechanism =>
      'group filter first, then consumer-side selector + == '
      '(idiomatic since 1.8.0)';

  @override
  Widget build(int cells) => Wrap(
    children: [
      for (var i = 0; i < cells; i++)
        JuiceSelector<CellsBloc, CellsState, int>(
          bloc: bloc,
          groups: {CellGroups.cell(i)},
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
  );
}
