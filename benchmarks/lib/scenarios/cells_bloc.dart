import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../counters.dart';
import 'variant.dart';

class SetCell {
  SetCell(this.index, this.value);
  final int index;
  final int value;
}

/// A Bloc (events, like Juice) — not a Cubit — so dispatch is comparable.
class CellsBloc extends Bloc<SetCell, List<int>> {
  CellsBloc(int cells) : super(List<int>.filled(cells, 0)) {
    on<SetCell>((e, emit) => emit(List<int>.of(state)..[e.index] = e.value));
  }
}

/// bloc with BlocSelector per cell — the idiomatic form.
class BlocSelectorVariant extends Variant {
  @override
  String get name => 'bloc · BlocSelector';
  @override
  String get framework => 'bloc';
  @override
  String get mechanism => 'consumer-side selector + ==';

  late CellsBloc bloc;

  @override
  void setUp(int cells) => bloc = CellsBloc(cells);

  @override
  Widget build(int cells) => BlocProvider<CellsBloc>.value(
    value: bloc,
    child: Wrap(
      children: [
        for (var i = 0; i < cells; i++)
          BlocSelector<CellsBloc, List<int>, int>(
            selector: (s) {
              Counters.selectorCalls++;
              return s[i];
            },
            builder: (_, v) {
              Counters.builds[i]++;
              return cellText(v);
            },
          ),
      ],
    ),
  );

  @override
  Future<void> update(int index, int value) {
    // bloc.add is fire-and-forget; "done" = the new state is observable.
    final next = bloc.stream.first;
    bloc.add(SetCell(index, value));
    return next;
  }

  @override
  Future<void> tearDown() => bloc.close();
}

/// bloc with plain BlocBuilder — every state change rebuilds every builder.
class BlocBuilderVariant extends BlocSelectorVariant {
  @override
  String get name => 'bloc · BlocBuilder';
  @override
  String get mechanism => 'no filter (the default)';

  @override
  Widget build(int cells) => BlocProvider<CellsBloc>.value(
    value: bloc,
    child: Wrap(
      children: [
        for (var i = 0; i < cells; i++)
          BlocBuilder<CellsBloc, List<int>>(
            builder: (_, s) {
              Counters.builds[i]++;
              return cellText(s[i]);
            },
          ),
      ],
    ),
  );
}
