import 'package:juice/juice.dart';

import '../flags_bloc.dart';
import '../flags_events.dart';
import '../flags_state.dart';

/// Handles [FlagsUpdatedEvent] — new values from the live stream. Emits only
/// the flags whose resolved value changed.
class FlagsUpdatedUseCase extends BlocUseCase<FlagsBloc, FlagsUpdatedEvent> {
  @override
  Future<void> execute(FlagsUpdatedEvent event) async {
    final old = bloc.state.values;
    bloc.applyFetched(event.values);
    final resolved = bloc.resolve();
    final changed = bloc.changedKeys(old, resolved);
    if (changed.isEmpty) return;

    emitUpdate(
      newState: bloc.state.copyWith(values: resolved, fetched: true, error: null),
      groupsToRebuild: {
        FlagsGroups.any,
        ...changed.map(FlagsGroups.flag),
      },
    );
  }
}
