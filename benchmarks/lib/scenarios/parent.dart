import 'package:juice/juice.dart';

import '../counters.dart';
import 'cells_juice.dart';
import 'variant.dart';

/// THE PARENT-REBUILD SCENARIO: N Juice leaf widgets under a parent that
/// rebuilds. The bloc never emits; every "update" bumps the parent, which
/// rebuilds all N leaves with fresh widget instances. A leaf keeps its bloc
/// subscription across those rebuilds (keyed on the bloc instance), and the
/// frame cost of a parent rebuild over N kept subscriptions is what this
/// prices.
class _Leaf extends StatelessJuiceWidget<CellsBloc> {
  _Leaf(this.index, {super.groups});
  final int index;

  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    Counters.builds[index]++;
    return cellText(bloc.state.cells[index]);
  }
}

class ParentJuiceGroupsVariant extends Variant {
  @override
  String get name => 'parent · juice · groups';
  @override
  String get framework => 'juice';
  @override
  String get mechanism =>
      'N grouped leaves under a parent that rebuilds; the bloc is silent';

  late CellsBloc bloc;
  late ValueNotifier<int> tick;

  @override
  void setUp(int cells) {
    bloc = CellsBloc(cells);
    tick = ValueNotifier<int>(0);
    BlocScope.register<CellsBloc>(() => bloc);
  }

  @override
  Widget build(int cells) => ValueListenableBuilder<int>(
    valueListenable: tick,
    builder: (_, _, _) => Wrap(
      children: [
        for (var i = 0; i < cells; i++) _Leaf(i, groups: {CellGroups.cell(i)}),
      ],
    ),
  );

  /// A parent rebuild, not a state change: [index] and [value] are unused.
  @override
  Future<void> update(int index, int value) async => tick.value++;

  @override
  Future<void> tearDown() async {
    tick.dispose();
    await BlocScope.endAll();
  }
}

List<Variant> parentVariants() => [ParentJuiceGroupsVariant()];
