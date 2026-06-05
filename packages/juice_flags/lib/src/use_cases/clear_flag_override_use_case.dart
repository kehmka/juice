import 'package:juice/juice.dart';

import '../flags_bloc.dart';
import '../flags_events.dart';
import '../flags_state.dart';

/// Handles [ClearFlagOverrideEvent] — revert to the fetched/default value.
class ClearFlagOverrideUseCase
    extends BlocUseCase<FlagsBloc, ClearFlagOverrideEvent> {
  @override
  Future<void> execute(ClearFlagOverrideEvent event) async {
    final old = bloc.state.values;
    bloc.clearOverride(event.key);
    final resolved = bloc.resolve();
    final changed = bloc.changedKeys(old, resolved);
    if (changed.isEmpty) return;

    emitUpdate(
      newState: bloc.state.copyWith(values: resolved),
      groupsToRebuild: {FlagsGroups.any, ...changed.map(FlagsGroups.flag)},
    );
  }
}
