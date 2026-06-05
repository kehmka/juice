import 'package:juice/juice.dart';

import '../flags_bloc.dart';
import '../flags_events.dart';
import '../flags_state.dart';

/// Handles [SetFlagOverrideEvent] — a local override wins over fetched values.
class SetFlagOverrideUseCase extends BlocUseCase<FlagsBloc, SetFlagOverrideEvent> {
  @override
  Future<void> execute(SetFlagOverrideEvent event) async {
    final old = bloc.state.values;
    bloc.setOverride(event.key, event.value);
    final resolved = bloc.resolve();
    final changed = bloc.changedKeys(old, resolved);
    if (changed.isEmpty) return;

    emitUpdate(
      newState: bloc.state.copyWith(values: resolved),
      groupsToRebuild: {FlagsGroups.any, ...changed.map(FlagsGroups.flag)},
    );
  }
}
