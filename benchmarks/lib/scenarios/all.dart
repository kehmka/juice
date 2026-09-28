import 'cells_bloc.dart';
import 'cells_juice.dart';
import 'cells_riverpod.dart';
import 'variant.dart';

export 'variant.dart';

/// Every variant, tuned first within each framework.
List<Variant> allVariants() => [
  JuiceGroupsVariant(),
  JuiceSelectorVariant(),
  JuiceUngroupedVariant(),
  BlocSelectorVariant(),
  BlocBuilderVariant(),
  RiverpodSelectVariant(),
  RiverpodWatchVariant(),
];
