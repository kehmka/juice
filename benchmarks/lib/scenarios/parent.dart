import 'package:juice/juice.dart';

import '../counters.dart';
import 'cells_juice.dart';
import 'variant.dart';

/// THE PARENT-REBUILD SCENARIO (2.0 docket item H): N Juice leaf widgets
/// under a parent that rebuilds. The bloc never emits; every "update" bumps
/// the parent, which rebuilds all N leaves with fresh widget instances. Before
/// 2.0.0 each leaf built a NEW filtered stream in `build`, so every parent
/// rebuild cancelled and re-listened N subscriptions; 2.0.0 keeps the
/// subscription while the bloc, groups and key are unchanged. The frame cost
/// per parent rebuild is what this prices — before and after.
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
  final tick = ValueNotifier<int>(0);

  @override
  void setUp(int cells) {
    bloc = CellsBloc(cells);
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
  Future<void> tearDown() => BlocScope.endAll();
}

List<Variant> parentVariants() => [ParentJuiceGroupsVariant()];
